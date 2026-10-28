"""
Unit & Integration Tests for FocusDNS GeoDNS & Latency-Aware Topology Routing Engine
====================================================================================
Comprehensive validation suite testing:
  1. Spherical Geodesic Haversine Great-Circle Distance Calculations
  2. Sub-microsecond Bitwise Radix Trie GeoIP Lookups for IPv4 and IPv6
  3. Multi-tier Routing Policies:
     - COUNTRY_FIRST (Exact country match -> Continent fallback -> Global nearest)
     - CONTINENT_FIRST (Regional continent containment)
     - NEAREST_GEODESIC (Pure spherical proximity)
     - WEIGHTED_PROXIMITY (Distance vs. Capacity weight score)
  4. Real-time Multi-Region Health Checking & Automatic Regional Failover
  5. Geo-Fencing Policies (Country blacklisting, Continent blocking, Whitelists, Redirection)
  6. EDNS Client Subnet (ECS - RFC 7871) End-User IP Override Routing
"""

import unittest
from server.engine.geodns import (
    GeoCoordinates,
    GeoLocation,
    EdgeEndpoint,
    GeoEndpointPool,
    GeoFencingPolicy,
    GeoIPDatabase,
    GeoDNSEngine,
    RoutingStrategy,
    HealthState,
    GeoRoutingDecision,
)


class TestHaversineDistance(unittest.TestCase):
    """Tests great-circle distance computations between global coordinates."""

    def test_identical_coordinates_zero_distance(self):
        c = GeoCoordinates(37.7749, -122.4194)  # San Francisco
        self.assertAlmostEqual(c.distance_to(c), 0.0, places=2)

    def test_sf_to_mountain_view(self):
        sf = GeoCoordinates(37.7749, -122.4194)
        mv = GeoCoordinates(37.4220, -122.0841)
        dist = sf.distance_to(mv)
        # Expected great-circle distance is ~49 - 52 km
        self.assertGreater(dist, 45.0)
        self.assertLess(dist, 55.0)

    def test_london_to_frankfurt(self):
        london = GeoCoordinates(51.5074, -0.1278)
        frankfurt = GeoCoordinates(50.1109, 8.6821)
        dist = london.distance_to(frankfurt)
        # Expected great-circle distance is ~630 - 645 km
        self.assertGreater(dist, 620.0)
        self.assertLess(dist, 650.0)

    def test_new_york_to_tokyo(self):
        nyc = GeoCoordinates(40.7128, -74.0060)
        tokyo = GeoCoordinates(35.6762, 139.6503)
        dist = nyc.distance_to(tokyo)
        # Expected distance ~10,800 - 10,900 km
        self.assertGreater(dist, 10700.0)
        self.assertLess(dist, 11000.0)


class TestGeoIPRadixTrie(unittest.TestCase):
    """Tests in-memory CIDR longest prefix matching for IPv4 and IPv6."""

    def setUp(self):
        self.db = GeoIPDatabase()

    def test_ipv4_lookup_known_subnets(self):
        # US Google DNS
        loc_us = self.db.lookup("8.8.8.8")
        self.assertEqual(loc_us.country_code, "US")
        self.assertEqual(loc_us.continent_code, "NA")

        # Germany Frankfurt
        loc_de = self.db.lookup("193.99.144.5")
        self.assertEqual(loc_de.country_code, "DE")
        self.assertEqual(loc_de.continent_code, "EU")

        # India Mumbai / Bangalore
        loc_in = self.db.lookup("106.51.5.10")
        self.assertEqual(loc_in.country_code, "IN")
        self.assertEqual(loc_in.continent_code, "AS")

        # Brazil
        loc_br = self.db.lookup("200.160.2.1")
        self.assertEqual(loc_br.country_code, "BR")
        self.assertEqual(loc_br.continent_code, "SA")

    def test_ipv6_lookup(self):
        loc_v6 = self.db.lookup("2001:4860:4860::8888")
        self.assertEqual(loc_v6.country_code, "US")
        self.assertEqual(loc_v6.continent_code, "NA")

    def test_unknown_ip_fallback(self):
        # Unrouted test IP
        loc_unknown = self.db.lookup("198.18.0.1")
        self.assertIsNotNone(loc_unknown)
        self.assertEqual(loc_unknown.ip_prefix, "0.0.0.0/0")

    def test_custom_csv_loading(self):
        csv_data = [
            "# Custom ISP entries",
            "198.18.50.0/24,IS,Iceland,EU,64.1466,-21.9426,Reykjavik,CAP,1234",
            "198.18.60.0/24,JP,Japan Cloud,AS,35.6895,139.6917,Tokyo,Tokyo,5678",
        ]
        inserted = self.db.load_csv(csv_data)
        self.assertEqual(inserted, 2)

        loc_is = self.db.lookup("198.18.50.12")
        self.assertEqual(loc_is.country_code, "IS")
        self.assertEqual(loc_is.city, "Reykjavik")
        self.assertEqual(loc_is.asn, 1234)


class TestGeoEndpointPoolAndPolicies(unittest.TestCase):
    """Tests routing algorithms, load balancing, and health state failover."""

    def setUp(self):
        self.pool = GeoEndpointPool("test-pool", strategy=RoutingStrategy.COUNTRY_FIRST)

        # US Endpoint
        self.ep_us = EdgeEndpoint(
            endpoint_id="us-east",
            name="Virginia Node",
            ipv4_address="198.51.100.10",
            coordinates=GeoCoordinates(38.9072, -77.0369),
            country_code="US",
            continent_code="NA",
            weight=100,
        )
        # EU Endpoint
        self.ep_eu = EdgeEndpoint(
            endpoint_id="eu-de",
            name="Frankfurt Node",
            ipv4_address="198.51.100.30",
            coordinates=GeoCoordinates(50.1109, 8.6821),
            country_code="DE",
            continent_code="EU",
            weight=100,
        )
        # AS Endpoint
        self.ep_as = EdgeEndpoint(
            endpoint_id="as-sg",
            name="Singapore Node",
            ipv4_address="198.51.100.60",
            coordinates=GeoCoordinates(1.3521, 103.8198),
            country_code="SG",
            continent_code="AS",
            weight=100,
        )

        self.pool.add_endpoint(self.ep_us)
        self.pool.add_endpoint(self.ep_eu)
        self.pool.add_endpoint(self.ep_as)

    def test_country_first_routing(self):
        # Client in US matches US endpoint
        us_loc = GeoLocation("8.8.8.0/24", "US", "United States", "NA", GeoCoordinates(37.751, -122.42))
        selected, failover, reason = self.pool.select_endpoint(us_loc)
        self.assertEqual(selected.endpoint_id, "us-east")
        self.assertFalse(failover)
        self.assertIn("Country match: US", reason)

        # Client in France (EU) does not match DE exactly, falls back to EU continent node
        fr_loc = GeoLocation("82.0.0.0/10", "FR", "France", "EU", GeoCoordinates(48.8566, 2.3522))
        selected_fr, failover_fr, reason_fr = self.pool.select_endpoint(fr_loc)
        self.assertEqual(selected_fr.endpoint_id, "eu-de")
        self.assertTrue(failover_fr)
        self.assertIn("continent fallback", reason_fr)

    def test_health_check_regional_failover(self):
        # Germany client normally routes to Frankfurt
        de_loc = GeoLocation("193.99.144.0/24", "DE", "Germany", "EU", GeoCoordinates(50.1109, 8.6821))

        # Mark Frankfurt UNHEALTHY
        self.pool.update_health("eu-de", HealthState.UNHEALTHY)

        # Now Germany client should failover to global closest healthy node (Virginia us-east)
        selected, failover, reason = self.pool.select_endpoint(de_loc)
        self.assertEqual(selected.endpoint_id, "us-east")
        self.assertTrue(failover)

    def test_all_endpoints_down_emergency_fallback(self):
        # Mark all endpoints unhealthy
        self.pool.update_health("us-east", HealthState.UNHEALTHY)
        self.pool.update_health("eu-de", HealthState.UNHEALTHY)
        self.pool.update_health("as-sg", HealthState.UNHEALTHY)

        any_loc = GeoLocation("1.1.1.0/24", "US", "United States", "NA", GeoCoordinates(37.77, -122.41))
        selected, failover, reason = self.pool.select_endpoint(any_loc)
        self.assertIsNotNone(selected)
        self.assertTrue(failover)
        self.assertIn("Emergency", reason)

    def test_nearest_geodesic_strategy(self):
        self.pool.strategy = RoutingStrategy.NEAREST_GEODESIC

        # Client near Singapore
        sea_loc = GeoLocation("103.0.0.0/10", "MY", "Malaysia", "AS", GeoCoordinates(3.1390, 101.6869))
        selected, _, _ = self.pool.select_endpoint(sea_loc)
        self.assertEqual(selected.endpoint_id, "as-sg")


class TestGeoFencingPolicies(unittest.TestCase):
    """Tests compliance policies and geographic access restrictions."""

    def setUp(self):
        self.fencing = GeoFencingPolicy()

    def test_block_country(self):
        self.fencing.block_country("RU")

        loc_allowed = GeoLocation("1.1.1.0/24", "US", "United States", "NA", GeoCoordinates(0, 0))
        act_ok, _ = self.fencing.evaluate(loc_allowed)
        self.assertEqual(act_ok, "allow")

        loc_blocked = GeoLocation("195.0.0.0/16", "RU", "Russia", "EU", GeoCoordinates(0, 0))
        act_block, reason = self.fencing.evaluate(loc_blocked)
        self.assertEqual(act_block, "block")
        self.assertIn("geo-blocked", reason)

    def test_whitelist_countries_only(self):
        self.fencing.allow_only_countries(["US", "CA", "GB"])

        loc_us = GeoLocation("8.8.8.0/24", "US", "USA", "NA", GeoCoordinates(0, 0))
        act_us, _ = self.fencing.evaluate(loc_us)
        self.assertEqual(act_us, "allow")

        loc_de = GeoLocation("193.0.0.0/16", "DE", "Germany", "EU", GeoCoordinates(0, 0))
        act_de, _ = self.fencing.evaluate(loc_de)
        self.assertEqual(act_de, "block")

    def test_traffic_redirection(self):
        self.fencing.set_redirect("CN", target_pool="china-shield-pool")

        loc_cn = GeoLocation("115.0.0.0/16", "CN", "China", "AS", GeoCoordinates(0, 0))
        act, reason = self.fencing.evaluate(loc_cn)
        self.assertEqual(act, "redirect:china-shield-pool")


class TestGeoDNSEngineFullFlow(unittest.TestCase):
    """Tests integrated GeoDNS resolution with ECS override."""

    def setUp(self):
        self.engine = GeoDNSEngine()

    def test_resolve_default_domain(self):
        # example.com is pre-bound to 'global-web' pool
        # Client query from Germany
        res = self.engine.resolve("example.com", client_ip="193.99.144.1")
        self.assertEqual(res.policy_action, "allow")
        self.assertEqual(res.selected_endpoint.country_code, "DE")
        self.assertEqual(res.selected_endpoint.endpoint_id, "eu-central-1")

    def test_resolve_with_ecs_override(self):
        # Resolver IP is in US, but ECS subnet is in Japan
        res = self.engine.resolve(
            "example.com",
            client_ip="8.8.8.8",            # US resolver
            ecs_ip="103.22.200.5",          # Tokyo, Japan ECS client
        )
        self.assertEqual(res.policy_action, "allow")
        self.assertEqual(res.client_location.country_code, "JP")
        # Should route to Tokyo edge cluster
        self.assertEqual(res.selected_endpoint.endpoint_id, "ap-northeast-1")


if __name__ == "__main__":
    unittest.main()
