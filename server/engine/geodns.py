"""
FocusGuard GeoDNS & Latency-Aware Topology Routing Engine
==========================================================
Carrier-grade geographic DNS routing engine that resolves client queries to
the topologically and geographically nearest server cluster or CDN POP.

Key Capabilities:
  1. High-Performance Radix / CIDR GeoIP Lookup:
     - In-memory radix tree mapping IPv4 and IPv6 prefixes to ISO country codes,
       continents, geographic coordinates (lat/long), and autonomous systems.
     - Pre-populated global dataset covering major global regions, plus CSV loader.
  2. Spherical Geodesic Distance (Haversine Formula):
     - Calculates precise great-circle distance between client/resolver coordinates
       and edge server clusters:
         d = 2 * R * arcsin(sqrt(sin^2(Δlat/2) + cos(lat1)*cos(lat2)*sin^2(Δlon/2)))
  3. EDNS Client Subnet (ECS - RFC 7871) Integration:
     - Extracts client subnet from EDNS0 ECS options to route queries based on the
       actual end-user's IP prefix rather than the recursive resolver's IP.
  4. Multi-Region Health-Checked Endpoint Pools:
     - Endpoints maintain active health status (HEALTHY, DEGRADED, UNHEALTHY).
     - Automatic multi-tier failover: Country Match -> Continent Match -> Global Nearest Healthy.
     - Weighted load distribution among equidistant or co-located edge servers.
  5. Geo-Fencing & Compliance Policies:
     - Allows/blocks resolution or diverts queries based on client origin country/continent
       (e.g., GDPR data sovereignty, sanctions compliance, localized CDN shielding).
"""

import math
import ipaddress
import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Dict, List, Optional, Tuple, Any

logger = logging.getLogger("FocusDNS.GeoDNS")

# Earth radius in kilometers (WGS-84 mean radius)
EARTH_RADIUS_KM = 6371.0088


class HealthState(Enum):
    HEALTHY = "healthy"
    DEGRADED = "degraded"
    UNHEALTHY = "unhealthy"


class RoutingStrategy(Enum):
    NEAREST_GEODESIC = "nearest_geodesic"
    CONTINENT_FIRST = "continent_first"
    COUNTRY_FIRST = "country_first"
    WEIGHTED_PROXIMITY = "weighted_proximity"
    FAILOVER_ONLY = "failover_only"


@dataclass(frozen=True)
class GeoCoordinates:
    """Geographic latitude and longitude coordinates."""
    latitude: float
    longitude: float

    def distance_to(self, other: "GeoCoordinates") -> float:
        """
        Compute great-circle distance to another coordinate using the Haversine formula.
        Returns distance in kilometers.
        """
        lat1_rad = math.radians(self.latitude)
        lon1_rad = math.radians(self.longitude)
        lat2_rad = math.radians(other.latitude)
        lon2_rad = math.radians(other.longitude)

        dlat = lat2_rad - lat1_rad
        dlon = lon2_rad - lon1_rad

        a = (
            math.sin(dlat / 2.0) ** 2
            + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(dlon / 2.0) ** 2
        )
        c = 2.0 * math.asin(math.sqrt(min(1.0, max(0.0, a))))
        return EARTH_RADIUS_KM * c


@dataclass
class GeoLocation:
    """Geographic profile associated with an IP address or subnet."""
    ip_prefix: str
    country_code: str          # ISO 3166-1 alpha-2 (e.g., 'US', 'DE', 'JP', 'IN')
    country_name: str
    continent_code: str        # 'NA', 'EU', 'AS', 'OC', 'SA', 'AF', 'AN'
    coordinates: GeoCoordinates
    city: str = ""
    region: str = ""
    asn: Optional[int] = None
    isp: str = ""


@dataclass
class EdgeEndpoint:
    """An edge server cluster, CDN POP, or service endpoint."""
    endpoint_id: str
    name: str
    ipv4_address: str
    ipv6_address: Optional[str] = None
    coordinates: GeoCoordinates = field(default_factory=lambda: GeoCoordinates(0.0, 0.0))
    country_code: str = "US"
    continent_code: str = "NA"
    weight: int = 100
    health: HealthState = HealthState.HEALTHY
    measured_latency_ms: float = 0.0
    active_connections: int = 0
    max_connections: int = 10000
    last_health_check: float = field(default_factory=time.time)

    def is_available(self) -> bool:
        """Endpoint can receive traffic if not unhealthy and under capacity."""
        return (
            self.health != HealthState.UNHEALTHY
            and self.active_connections < self.max_connections
        )


@dataclass
class GeoRoutingDecision:
    """The result of a GeoDNS resolution decision."""
    selected_endpoint: Optional[EdgeEndpoint]
    client_ip: str
    client_location: Optional[GeoLocation]
    distance_km: float
    routing_strategy: RoutingStrategy
    failover_occurred: bool = False
    policy_action: str = "allow"  # 'allow', 'block', 'divert'
    reason: str = ""


# Default Reference Coordinates for major continents and global hubs
CONTINENT_CENTROIDS = {
    "NA": GeoCoordinates(39.8283, -98.5795),   # North America
    "EU": GeoCoordinates(50.1109, 8.6821),     # Europe (Frankfurt)
    "AS": GeoCoordinates(34.0479, 100.6197),   # Asia
    "OC": GeoCoordinates(-25.2744, 133.7751),  # Oceania
    "SA": GeoCoordinates(-14.2350, -51.9253),  # South America
    "AF": GeoCoordinates(0.0236, 37.9062),     # Africa
}

DEFAULT_GEOIP_ENTRIES = [
    # North America
    ("8.8.8.0/24", "US", "United States", "NA", 37.751, -122.42, "San Francisco", "CA", 15169),
    ("1.1.1.0/24", "US", "United States", "NA", 37.7749, -122.4194, "San Francisco", "CA", 13335),
    ("12.0.0.0/8", "US", "United States", "NA", 38.0, -97.0, "Wichita", "KS", 7018),
    ("17.0.0.0/8", "US", "United States", "NA", 37.3382, -122.0081, "Cupertino", "CA", 714),
    ("24.0.0.0/11", "US", "United States", "NA", 40.7128, -74.0060, "New York", "NY", 7922),
    ("142.250.0.0/15", "US", "United States", "NA", 37.422, -122.084, "Mountain View", "CA", 15169),
    ("198.51.100.0/24", "US", "United States", "NA", 47.6062, -122.3321, "Seattle", "WA", 64512),
    ("192.0.2.0/24", "US", "United States", "NA", 34.0522, -118.2437, "Los Angeles", "CA", 64512),
    ("199.19.56.0/24", "US", "United States", "NA", 38.9072, -77.0369, "Washington DC", "DC", 26415),
    ("192.168.0.0/16", "US", "Private Network", "NA", 39.8283, -98.5795, "Local", "", 0),
    ("10.0.0.0/8", "US", "Private Network", "NA", 39.8283, -98.5795, "Local", "", 0),
    ("127.0.0.0/8", "US", "Loopback", "NA", 39.8283, -98.5795, "Local", "", 0),
    ("142.150.0.0/16", "CA", "Canada", "NA", 43.6532, -79.3832, "Toronto", "ON", 239),
    ("198.168.0.0/16", "CA", "Canada", "NA", 45.5017, -73.5673, "Montreal", "QC", 577),

    # Europe
    ("185.199.108.0/22", "NL", "Netherlands", "EU", 52.3676, 4.9041, "Amsterdam", "NH", 36459),
    ("80.0.0.0/8", "GB", "United Kingdom", "EU", 51.5074, -0.1278, "London", "ENG", 2856),
    ("151.0.0.0/16", "GB", "United Kingdom", "EU", 53.4808, -2.2426, "Manchester", "ENG", 5089),
    ("194.109.0.0/16", "NL", "Netherlands", "EU", 52.3676, 4.9041, "Amsterdam", "NH", 3265),
    ("193.99.144.0/24", "DE", "Germany", "EU", 50.1109, 8.6821, "Frankfurt", "HE", 3320),
    ("217.0.0.0/13", "DE", "Germany", "EU", 52.5200, 13.4050, "Berlin", "BE", 3320),
    ("82.0.0.0/10", "FR", "France", "EU", 48.8566, 2.3522, "Paris", "IDF", 12322),
    ("195.154.0.0/16", "FR", "France", "EU", 45.7640, 4.8357, "Lyon", "ARA", 12876),

    # Asia Pacific
    ("103.0.0.0/10", "AP", "Asia-Pacific", "AS", 1.3521, 103.8198, "Singapore", "", 13335),
    ("103.21.244.0/22", "SG", "Singapore", "AS", 1.3521, 103.8198, "Singapore", "", 13335),
    ("103.22.200.0/22", "JP", "Japan", "AS", 35.6762, 139.6503, "Tokyo", "Tokyo", 2516),
    ("118.0.0.0/11", "JP", "Japan", "AS", 34.6937, 135.5023, "Osaka", "Osaka", 4713),
    ("103.27.0.0/16", "IN", "India", "AS", 19.0760, 72.8777, "Mumbai", "MH", 55836),
    ("106.51.0.0/16", "IN", "India", "AS", 12.9716, 77.5946, "Bangalore", "KA", 45609),
    ("115.112.0.0/16", "IN", "India", "AS", 28.6139, 77.2090, "New Delhi", "DL", 4755),
    ("139.130.0.0/16", "AU", "Australia", "AS", -33.8688, 151.2093, "Sydney", "NSW", 1221),
    ("1.0.0.0/24", "AU", "Australia", "OC", -37.8136, 144.9631, "Melbourne", "VIC", 13335),

    # South America
    ("200.160.0.0/20", "BR", "Brazil", "SA", -23.5505, -46.6333, "Sao Paulo", "SP", 22548),
    ("186.192.0.0/13", "BR", "Brazil", "SA", -22.9068, -43.1729, "Rio de Janeiro", "RJ", 28573),

    # Africa
    ("197.80.0.0/16", "ZA", "South Africa", "AF", -26.2041, 28.0473, "Johannesburg", "GP", 37457),
    ("102.164.0.0/16", "ZA", "South Africa", "AF", -33.9249, 18.4241, "Cape Town", "WC", 36903),
    ("105.112.0.0/16", "NG", "Nigeria", "AF", 6.5244, 3.3792, "Lagos", "LA", 29465),

    # IPv6 Entries
    ("2001:4860::/32", "US", "Google LLC", "NA", 37.4220, -122.0841, "Mountain View", "CA", 15169),
    ("2606:4700::/32", "US", "Cloudflare", "NA", 37.7749, -122.4194, "San Francisco", "CA", 13335),
    ("2a00:1450::/32", "IE", "Google Ireland", "EU", 53.3498, -6.2603, "Dublin", "L", 15169),
    ("2404:6800::/32", "JP", "Google Tokyo", "AS", 35.6762, 139.6503, "Tokyo", "Tokyo", 15169),
]


class GeoIPRadixTrieNode:
    """Bitwise radix trie node for prefix matching."""
    def __init__(self):
        self.children: Dict[int, "GeoIPRadixTrieNode"] = {}
        self.location: Optional[GeoLocation] = None


class GeoIPDatabase:
    """
    High-performance in-memory CIDR lookup database supporting both IPv4 and IPv6.
    Uses binary bitwise radix trie for O(log(W)) lookup times (<1 µs).
    """

    def __init__(self):
        self._v4_root = GeoIPRadixTrieNode()
        self._v6_root = GeoIPRadixTrieNode()
        self._entry_count = 0
        self._fallback_location = GeoLocation(
            ip_prefix="0.0.0.0/0",
            country_code="US",
            country_name="Default Location",
            continent_code="NA",
            coordinates=GeoCoordinates(37.751, -122.42),
            city="San Francisco",
        )
        self._load_defaults()

    def _load_defaults(self):
        """Populate the default global CIDR lookup table."""
        for entry in DEFAULT_GEOIP_ENTRIES:
            cidr, cc, name, cont, lat, lon, city, region, asn = entry
            self.insert(
                GeoLocation(
                    ip_prefix=cidr,
                    country_code=cc,
                    country_name=name,
                    continent_code=cont,
                    coordinates=GeoCoordinates(lat, lon),
                    city=city,
                    region=region,
                    asn=asn,
                )
            )

    def insert(self, location: GeoLocation) -> None:
        """Insert a CIDR prefix into the appropriate radix trie."""
        try:
            net = ipaddress.ip_network(location.ip_prefix, strict=False)
        except ValueError:
            logger.warning(f"Invalid IP prefix in GeoIP DB: {location.ip_prefix}")
            return

        is_v4 = net.version == 4
        root = self._v4_root if is_v4 else self._v6_root
        max_bits = 32 if is_v4 else 128
        prefix_len = net.prefixlen

        # Convert network address to bit sequence
        net_int = int(net.network_address)
        curr = root
        for i in range(max_bits - 1, max_bits - 1 - prefix_len, -1):
            bit = (net_int >> i) & 1
            if bit not in curr.children:
                curr.children[bit] = GeoIPRadixTrieNode()
            curr = curr.children[bit]

        curr.location = location
        self._entry_count += 1

    def lookup(self, ip_str: str) -> GeoLocation:
        """
        Longest Prefix Match (LPM) lookup for an IP address.
        Returns matching GeoLocation, or fallback location if not found.
        """
        try:
            ip_obj = ipaddress.ip_address(ip_str.strip())
        except ValueError:
            return self._fallback_location

        is_v4 = ip_obj.version == 4
        root = self._v4_root if is_v4 else self._v6_root
        max_bits = 32 if is_v4 else 128
        ip_int = int(ip_obj)

        curr = root
        matched_loc: Optional[GeoLocation] = curr.location

        for i in range(max_bits - 1, -1, -1):
            bit = (ip_int >> i) & 1
            if bit not in curr.children:
                break
            curr = curr.children[bit]
            if curr.location is not None:
                matched_loc = curr.location

        return matched_loc or self._fallback_location

    @property
    def total_prefixes(self) -> int:
        return self._entry_count

    def load_csv(self, csv_lines: List[str]) -> int:
        """
        Load custom GeoIP database from CSV formatted lines:
        cidr,country_code,country_name,continent_code,lat,lon,city,region,asn
        """
        count = 0
        for line in csv_lines:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = [p.strip() for p in line.split(",")]
            if len(parts) >= 6:
                try:
                    cidr = parts[0]
                    cc = parts[1]
                    name = parts[2]
                    cont = parts[3]
                    lat = float(parts[4])
                    lon = float(parts[5])
                    city = parts[6] if len(parts) > 6 else ""
                    region = parts[7] if len(parts) > 7 else ""
                    asn = int(parts[8]) if len(parts) > 8 and parts[8].isdigit() else None
                    self.insert(
                        GeoLocation(
                            ip_prefix=cidr,
                            country_code=cc,
                            country_name=name,
                            continent_code=cont,
                            coordinates=GeoCoordinates(lat, lon),
                            city=city,
                            region=region,
                            asn=asn,
                        )
                    )
                    count += 1
                except Exception as e:
                    logger.debug(f"Error parsing GeoIP CSV line: {line}: {e}")
        return count


class GeoEndpointPool:
    """
    Named collection of edge servers with health states and load balancing policies.
    """

    def __init__(self, pool_name: str, strategy: RoutingStrategy = RoutingStrategy.NEAREST_GEODESIC):
        self.name = pool_name
        self.strategy = strategy
        self._endpoints: Dict[str, EdgeEndpoint] = {}
        self._rr_counters: Dict[str, int] = {}

    def add_endpoint(self, endpoint: EdgeEndpoint) -> None:
        self._endpoints[endpoint.endpoint_id] = endpoint

    def remove_endpoint(self, endpoint_id: str) -> Optional[EdgeEndpoint]:
        return self._endpoints.pop(endpoint_id, None)

    def get_endpoint(self, endpoint_id: str) -> Optional[EdgeEndpoint]:
        return self._endpoints.get(endpoint_id)

    def list_endpoints(self) -> List[EdgeEndpoint]:
        return list(self._endpoints.values())

    def update_health(self, endpoint_id: str, state: HealthState, latency_ms: Optional[float] = None) -> bool:
        ep = self._endpoints.get(endpoint_id)
        if ep:
            ep.health = state
            ep.last_health_check = time.time()
            if latency_ms is not None:
                ep.measured_latency_ms = latency_ms
            return True
        return False

    def select_endpoint(self, client_loc: GeoLocation) -> Tuple[Optional[EdgeEndpoint], bool, str]:
        """
        Select best endpoint for a given client geographic location according to the configured policy.
        Returns: (selected_endpoint, failover_occurred, reason)
        """
        all_eps = list(self._endpoints.values())
        if not all_eps:
            return None, False, "No endpoints in pool"

        available_eps = [ep for ep in all_eps if ep.is_available()]
        if not available_eps:
            # All down: Fallback to degraded endpoints or lowest load
            degraded = [ep for ep in all_eps if ep.health == HealthState.DEGRADED]
            if degraded:
                available_eps = degraded
            else:
                # Emergency: Return first endpoint despite unhealthy state
                return all_eps[0], True, "Emergency: All endpoints down, routing to primary fallback"

        if self.strategy == RoutingStrategy.COUNTRY_FIRST:
            # 1. Try exact country match
            country_matches = [ep for ep in available_eps if ep.country_code == client_loc.country_code]
            if country_matches:
                chosen = self._select_by_proximity(client_loc.coordinates, country_matches)
                return chosen, False, f"Country match: {client_loc.country_code}"
            # 2. Fall back to continent match
            continent_matches = [ep for ep in available_eps if ep.continent_code == client_loc.continent_code]
            if continent_matches:
                chosen = self._select_by_proximity(client_loc.coordinates, continent_matches)
                return chosen, True, f"Country miss, continent fallback: {client_loc.continent_code}"
            # 3. Fall back to global nearest
            chosen = self._select_by_proximity(client_loc.coordinates, available_eps)
            return chosen, True, "Continent miss, global nearest fallback"

        elif self.strategy == RoutingStrategy.CONTINENT_FIRST:
            # 1. Try continent match
            continent_matches = [ep for ep in available_eps if ep.continent_code == client_loc.continent_code]
            if continent_matches:
                chosen = self._select_by_proximity(client_loc.coordinates, continent_matches)
                return chosen, False, f"Continent match: {client_loc.continent_code}"
            # 2. Fall back to global nearest
            chosen = self._select_by_proximity(client_loc.coordinates, available_eps)
            return chosen, True, "Continent miss, global nearest fallback"

        elif self.strategy == RoutingStrategy.WEIGHTED_PROXIMITY:
            # Proximity weighted by inverse distance and endpoint capacity weight
            chosen = self._select_by_weighted_proximity(client_loc.coordinates, available_eps)
            return chosen, False, "Weighted proximity"

        else:
            # Default: Pure Geodesic Haversine Proximity
            chosen = self._select_by_proximity(client_loc.coordinates, available_eps)
            return chosen, False, "Nearest geodesic distance"

    def _select_by_proximity(self, client_coord: GeoCoordinates, endpoints: List[EdgeEndpoint]) -> EdgeEndpoint:
        """Select endpoint with minimal Haversine distance."""
        best_ep = endpoints[0]
        min_dist = float("inf")
        for ep in endpoints:
            dist = client_coord.distance_to(ep.coordinates)
            if dist < min_dist:
                min_dist = dist
                best_ep = ep
        return best_ep

    def _select_by_weighted_proximity(self, client_coord: GeoCoordinates, endpoints: List[EdgeEndpoint]) -> EdgeEndpoint:
        """
        Select endpoint balancing geographic proximity with configured endpoint weights.
        Score = Weight / (Distance_km + 50.0)
        Higher score wins.
        """
        best_ep = endpoints[0]
        best_score = -1.0
        for ep in endpoints:
            dist = client_coord.distance_to(ep.coordinates)
            # Add 50 km damping factor to prevent zero-division on co-located nodes
            score = float(ep.weight) / (dist + 50.0)
            if score > best_score:
                best_score = score
                best_ep = ep
        return best_ep


class GeoFencingPolicy:
    """
    Geo-fencing policy rule for blocking, allowing, or redirecting specific geographic zones.
    """

    def __init__(self):
        self.blocked_countries: set = set()
        self.blocked_continents: set = set()
        self.allowed_countries_only: Optional[set] = None
        self.redirect_map: Dict[str, str] = {}  # country_code -> redirect_pool

    def block_country(self, country_code: str) -> None:
        self.blocked_countries.add(country_code.upper())

    def unblock_country(self, country_code: str) -> None:
        self.blocked_countries.discard(country_code.upper())

    def block_continent(self, continent_code: str) -> None:
        self.blocked_continents.add(continent_code.upper())

    def allow_only_countries(self, country_codes: List[str]) -> None:
        self.allowed_countries_only = {c.upper() for c in country_codes}

    def set_redirect(self, country_code: str, target_pool: str) -> None:
        self.redirect_map[country_code.upper()] = target_pool

    def evaluate(self, location: GeoLocation) -> Tuple[str, str]:
        """
        Evaluate location against geo-fence policies.
        Returns: (action, reason) where action is 'allow', 'block', or 'redirect:<pool>'
        """
        cc = location.country_code.upper()
        cont = location.continent_code.upper()

        if self.allowed_countries_only is not None and cc not in self.allowed_countries_only:
            return "block", f"Country {cc} not in allowed countries whitelist"

        if cc in self.blocked_countries:
            return "block", f"Country {cc} is geo-blocked by policy"

        if cont in self.blocked_continents:
            return "block", f"Continent {cont} is geo-blocked by policy"

        if cc in self.redirect_map:
            return f"redirect:{self.redirect_map[cc]}", f"Traffic from {cc} redirected to {self.redirect_map[cc]}"

        return "allow", "Permitted by geo-fencing policy"


class GeoDNSEngine:
    """
    Comprehensive GeoDNS Routing Subsystem.
    Integrates GeoIP Radix database, health-checked endpoint pools, and geo-fencing policies.
    """

    def __init__(self):
        self.geoip = GeoIPDatabase()
        self.pools: Dict[str, GeoEndpointPool] = {}
        self.fencing = GeoFencingPolicy()
        self.domain_pool_bindings: Dict[str, str] = {}  # fqdn -> pool_name

        # Performance & telemetry statistics
        self._stats = {
            "total_queries": 0,
            "geo_hits": 0,
            "fallback_hits": 0,
            "blocked_by_geofence": 0,
            "failover_events": 0,
            "ecs_queries": 0,
        }

        self._setup_default_infrastructure()

    def _setup_default_infrastructure(self):
        """Provision a production-grade multi-region edge deployment topology."""
        global_pool = GeoEndpointPool("global-web", strategy=RoutingStrategy.COUNTRY_FIRST)

        # North America: US-East (Virginia), US-West (California)
        global_pool.add_endpoint(
            EdgeEndpoint(
                endpoint_id="us-east-1",
                name="Virginia Cloud Edge",
                ipv4_address="198.51.100.10",
                ipv6_address="2001:db8:1::10",
                coordinates=GeoCoordinates(38.9072, -77.0369),
                country_code="US",
                continent_code="NA",
                weight=100,
            )
        )
        global_pool.add_endpoint(
            EdgeEndpoint(
                endpoint_id="us-west-1",
                name="California Cloud Edge",
                ipv4_address="198.51.100.20",
                ipv6_address="2001:db8:1::20",
                coordinates=GeoCoordinates(37.7749, -122.4194),
                country_code="US",
                continent_code="NA",
                weight=100,
            )
        )

        # Europe: Frankfurt, London
        global_pool.add_endpoint(
            EdgeEndpoint(
                endpoint_id="eu-central-1",
                name="Frankfurt Edge Cluster",
                ipv4_address="198.51.100.30",
                ipv6_address="2001:db8:2::30",
                coordinates=GeoCoordinates(50.1109, 8.6821),
                country_code="DE",
                continent_code="EU",
                weight=100,
            )
        )
        global_pool.add_endpoint(
            EdgeEndpoint(
                endpoint_id="eu-west-1",
                name="London Edge Cluster",
                ipv4_address="198.51.100.40",
                ipv6_address="2001:db8:2::40",
                coordinates=GeoCoordinates(51.5074, -0.1278),
                country_code="GB",
                continent_code="EU",
                weight=100,
            )
        )

        # Asia Pacific: Tokyo, Singapore, Mumbai
        global_pool.add_endpoint(
            EdgeEndpoint(
                endpoint_id="ap-northeast-1",
                name="Tokyo Edge Cluster",
                ipv4_address="198.51.100.50",
                ipv6_address="2001:db8:3::50",
                coordinates=GeoCoordinates(35.6762, 139.6503),
                country_code="JP",
                continent_code="AS",
                weight=100,
            )
        )
        global_pool.add_endpoint(
            EdgeEndpoint(
                endpoint_id="ap-southeast-1",
                name="Singapore Edge Hub",
                ipv4_address="198.51.100.60",
                ipv6_address="2001:db8:3::60",
                coordinates=GeoCoordinates(1.3521, 103.8198),
                country_code="SG",
                continent_code="AS",
                weight=100,
            )
        )
        global_pool.add_endpoint(
            EdgeEndpoint(
                endpoint_id="ap-south-1",
                name="Mumbai Edge Hub",
                ipv4_address="198.51.100.70",
                ipv6_address="2001:db8:3::70",
                coordinates=GeoCoordinates(19.0760, 72.8777),
                country_code="IN",
                continent_code="AS",
                weight=100,
            )
        )

        # South America: Sao Paulo
        global_pool.add_endpoint(
            EdgeEndpoint(
                endpoint_id="sa-east-1",
                name="Sao Paulo Edge POP",
                ipv4_address="198.51.100.80",
                ipv6_address="2001:db8:4::80",
                coordinates=GeoCoordinates(-23.5505, -46.6333),
                country_code="BR",
                continent_code="SA",
                weight=100,
            )
        )

        # Oceania: Sydney
        global_pool.add_endpoint(
            EdgeEndpoint(
                endpoint_id="ap-southeast-2",
                name="Sydney Edge POP",
                ipv4_address="198.51.100.90",
                ipv6_address="2001:db8:5::90",
                coordinates=GeoCoordinates(-33.8688, 151.2093),
                country_code="AU",
                continent_code="OC",
                weight=100,
            )
        )

        self.register_pool(global_pool)
        self.bind_domain("example.com", "global-web")
        self.bind_domain("cdn.focusguard.local", "global-web")

    def register_pool(self, pool: GeoEndpointPool) -> None:
        self.pools[pool.name] = pool

    def bind_domain(self, domain: str, pool_name: str) -> None:
        self.domain_pool_bindings[domain.lower().rstrip(".")] = pool_name

    def unbind_domain(self, domain: str) -> None:
        self.domain_pool_bindings.pop(domain.lower().rstrip("."), None)

    def resolve(
        self,
        domain: str,
        client_ip: str,
        ecs_ip: Optional[str] = None,
    ) -> GeoRoutingDecision:
        """
        Resolve a DNS domain request to the optimal edge endpoint using GeoDNS.
        Respects EDNS Client Subnet (ECS) if supplied, falling back to client_ip.
        """
        self._stats["total_queries"] += 1
        effective_ip = ecs_ip if ecs_ip else client_ip

        if ecs_ip:
            self._stats["ecs_queries"] += 1

        # 1. GeoIP Lookup for effective IP
        loc = self.geoip.lookup(effective_ip)
        if loc.ip_prefix == "0.0.0.0/0":
            self._stats["fallback_hits"] += 1
        else:
            self._stats["geo_hits"] += 1

        # 2. Check Geo-Fencing Policies
        action, reason = self.fencing.evaluate(loc)
        if action == "block":
            self._stats["blocked_by_geofence"] += 1
            return GeoRoutingDecision(
                selected_endpoint=None,
                client_ip=effective_ip,
                client_location=loc,
                distance_km=0.0,
                routing_strategy=RoutingStrategy.COUNTRY_FIRST,
                failover_occurred=False,
                policy_action="block",
                reason=reason,
            )

        # 3. Determine Endpoint Pool
        clean_domain = domain.lower().rstrip(".")
        pool_name = self.domain_pool_bindings.get(clean_domain)

        # Check for policy redirection override
        if action.startswith("redirect:"):
            pool_name = action.split(":", 1)[1]

        if not pool_name or pool_name not in self.pools:
            # Default to first available pool
            if self.pools:
                pool_name = next(iter(self.pools.keys()))
            else:
                return GeoRoutingDecision(
                    selected_endpoint=None,
                    client_ip=effective_ip,
                    client_location=loc,
                    distance_km=0.0,
                    routing_strategy=RoutingStrategy.COUNTRY_FIRST,
                    failover_occurred=False,
                    policy_action="error",
                    reason=f"No routing pool registered for domain: {domain}",
                )

        pool = self.pools[pool_name]

        # 4. Select Optimal Endpoint from Pool
        ep, failover, sel_reason = pool.select_endpoint(loc)
        if failover:
            self._stats["failover_events"] += 1

        dist = loc.coordinates.distance_to(ep.coordinates) if ep else 0.0

        return GeoRoutingDecision(
            selected_endpoint=ep,
            client_ip=effective_ip,
            client_location=loc,
            distance_km=round(dist, 2),
            routing_strategy=pool.strategy,
            failover_occurred=failover,
            policy_action="allow",
            reason=sel_reason,
        )

    def get_stats(self) -> Dict[str, Any]:
        """Return engine metrics and health status."""
        total_endpoints = sum(len(p.list_endpoints()) for p in self.pools.values())
        healthy_endpoints = sum(
            len([e for e in p.list_endpoints() if e.health == HealthState.HEALTHY])
            for p in self.pools.values()
        )
        return {
            **self._stats,
            "total_prefixes_loaded": self.geoip.total_prefixes,
            "total_pools": len(self.pools),
            "total_endpoints": total_endpoints,
            "healthy_endpoints": healthy_endpoints,
            "blocked_countries": list(self.fencing.blocked_countries),
            "blocked_continents": list(self.fencing.blocked_continents),
        }
