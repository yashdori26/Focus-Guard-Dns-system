"""
Unit & Integration Tests for FocusDNS GeoDNS Global Datasets & Latency Topology
================================================================================
Validates:
  1. ISO 3166-1 alpha-2 Global Countries & Centroid Database (240+ entries)
  2. Public Cloud Datacenter Regions & Geographic Proximity Resolution (AWS, GCP, Azure)
  3. Optical Fiber Propagation Delay & Subsea Cable RTT Matrix Estimation
  4. Global Carrier Subnet Allocations (AT&T, Verizon, Deutsche Telekom, NTT, Singtel, Jio)
"""

import unittest
from server.engine.geodns import GeoCoordinates, GeoIPDatabase
from server.engine.geodns_data import (
    GLOBAL_COUNTRY_DATABASE,
    MAJOR_CLOUD_REGIONS,
    INTER_CONTINENT_LATENCY_MATRIX,
    estimate_fiber_rtt_ms,
    get_country_profile,
    find_nearest_cloud_region,
    populate_global_carrier_cidrs,
)


class TestGeoDNSDataGlobalCountries(unittest.TestCase):
    """Tests ISO country data lookup."""

    def test_lookup_major_countries(self):
        us = get_country_profile("US")
        self.assertIsNotNone(us)
        self.assertEqual(us.name, "United States")
        self.assertEqual(us.continent, "NA")

        de = get_country_profile("de")  # Case insensitive
        self.assertIsNotNone(de)
        self.assertEqual(de.name, "Germany")
        self.assertEqual(de.continent, "EU")

        jp = get_country_profile("JP")
        self.assertIsNotNone(jp)
        self.assertEqual(jp.name, "Japan")
        self.assertEqual(jp.continent, "AS")

    def test_nonexistent_country(self):
        self.assertIsNone(get_country_profile("ZZ"))


class TestCloudRegionProximity(unittest.TestCase):
    """Tests finding closest cloud datacenters."""

    def test_find_nearest_aws_region(self):
        # Client in London, UK
        london = GeoCoordinates(51.5074, -0.1278)
        reg = find_nearest_cloud_region(london, provider="AWS")
        self.assertEqual(reg.region_id, "eu-west-2")
        self.assertEqual(reg.city, "London")

    def test_find_nearest_gcp_region(self):
        # Client in Frankfurt, Germany
        frankfurt = GeoCoordinates(50.1109, 8.6821)
        reg = find_nearest_cloud_region(frankfurt, provider="GCP")
        self.assertEqual(reg.region_id, "europe-west3")

    def test_find_nearest_azure_region(self):
        # Client in Tokyo, Japan
        tokyo = GeoCoordinates(35.6762, 139.6503)
        reg = find_nearest_cloud_region(tokyo, provider="Azure")
        self.assertEqual(reg.region_id, "japaneast")


class TestFiberLatencyModel(unittest.TestCase):
    """Tests optical propagation delay and submarine cable matrix estimations."""

    def test_transatlantic_latency(self):
        # New York to London
        nyc = GeoCoordinates(40.7128, -74.0060)
        london = GeoCoordinates(51.5074, -0.1278)
        rtt = estimate_fiber_rtt_ms(nyc, london, cont1="NA", cont2="EU")

        # Real-world transatlantic RTT is ~70 - 85 ms
        self.assertGreaterEqual(rtt, 70.0)
        self.assertLessEqual(rtt, 95.0)

    def test_transpacific_latency(self):
        # San Francisco to Tokyo
        sf = GeoCoordinates(37.7749, -122.4194)
        tokyo = GeoCoordinates(35.6762, 139.6503)
        rtt = estimate_fiber_rtt_ms(sf, tokyo, cont1="NA", cont2="AS")

        # Real-world transpacific RTT is ~130 - 150 ms
        self.assertGreaterEqual(rtt, 130.0)
        self.assertLessEqual(rtt, 160.0)

    def test_intra_europe_latency(self):
        # Paris to Frankfurt (~480 km)
        paris = GeoCoordinates(48.8566, 2.3522)
        frankfurt = GeoCoordinates(50.1109, 8.6821)
        rtt = estimate_fiber_rtt_ms(paris, frankfurt, cont1="EU", cont2="EU")

        # Expected RTT ~15 - 25 ms
        self.assertGreaterEqual(rtt, 15.0)
        self.assertLessEqual(rtt, 35.0)


class TestGlobalCarrierCIDRPopulation(unittest.TestCase):
    """Tests populating GeoIPDatabase with major global telecom providers."""

    def test_populate_carrier_subnets(self):
        db = GeoIPDatabase()
        initial_count = db.total_prefixes

        added = populate_global_carrier_cidrs(db)
        self.assertGreater(added, 20)
        self.assertEqual(db.total_prefixes, initial_count + added)

        # Test carrier lookups
        # AT&T (US)
        loc_att = db.lookup("12.5.10.1")
        self.assertEqual(loc_att.country_code, "US")
        self.assertIn("AT&T", loc_att.country_name)

        # Deutsche Telekom (DE)
        loc_dt = db.lookup("62.153.10.1")
        self.assertEqual(loc_dt.country_code, "DE")
        self.assertIn("Deutsche Telekom", loc_dt.country_name)

        # Singtel (SG)
        loc_singtel = db.lookup("165.21.5.1")
        self.assertEqual(loc_singtel.country_code, "SG")
        self.assertIn("Singtel", loc_singtel.country_name)

        # Reliance Jio (IN)
        loc_jio = db.lookup("49.32.1.1")
        self.assertEqual(loc_jio.country_code, "IN")
        self.assertIn("Reliance Jio", loc_jio.country_name)


if __name__ == "__main__":
    unittest.main()
