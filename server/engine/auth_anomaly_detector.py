"""
FocusDNS Enterprise Authentication Anomaly Detector & Geo-Velocity Engine.
Provides statistical and heuristic threat evaluation for phone-based logins:
- Impossible travel / geo-velocity anomaly detection via Haversine great-circle metrics
- Carrier type heuristics (Mobile, MNO, MVNO, VoIP, Disposable)
- Device fingerprint consistency and SIM-swap risk scoring
- Multi-tier Token-Bucket rate limiting and brute-force mitigation
- Weighted ensemble Risk Scorer with enterprise SIEM audit trails
"""

import math
import time
import re
from typing import Dict, Any, List, Optional, Tuple
from dataclasses import dataclass, field
from enum import Enum


class RiskLevel(str, Enum):
    SAFE = "SAFE"
    LOW = "LOW"
    MEDIUM = "MEDIUM"
    HIGH = "HIGH"
    CRITICAL = "CRITICAL"


class RecommendedAction(str, Enum):
    ALLOW = "ALLOW"
    CHALLENGE = "CHALLENGE"
    DELAY = "DELAY"
    BLOCK = "BLOCK"


@dataclass
class GeoCoordinate:
    latitude: float
    longitude: float
    country_code: str
    city: str = ""


# Country centroid coordinates database for global geo-velocity calculations
COUNTRY_COORDINATES: Dict[str, GeoCoordinate] = {
    "US": GeoCoordinate(37.0902, -95.7129, "US", "Washington DC"),
    "IN": GeoCoordinate(20.5937, 78.9629, "IN", "New Delhi"),
    "GB": GeoCoordinate(55.3781, -3.4360, "GB", "London"),
    "CA": GeoCoordinate(56.1304, -106.3468, "CA", "Ottawa"),
    "AU": GeoCoordinate(-25.2744, 133.7751, "AU", "Canberra"),
    "DE": GeoCoordinate(51.1657, 10.4515, "DE", "Berlin"),
    "FR": GeoCoordinate(46.2276, 2.2137, "FR", "Paris"),
    "JP": GeoCoordinate(36.2048, 138.2529, "JP", "Tokyo"),
    "SG": GeoCoordinate(1.3521, 103.8198, "SG", "Singapore"),
    "BR": GeoCoordinate(-14.2350, -51.9253, "BR", "Brasilia"),
    "ZA": GeoCoordinate(-30.5595, 22.9375, "ZA", "Pretoria"),
    "AE": GeoCoordinate(23.4241, 53.8478, "AE", "Abu Dhabi"),
    "NL": GeoCoordinate(52.1326, 5.2913, "NL", "Amsterdam"),
    "CH": GeoCoordinate(46.8182, 8.2275, "CH", "Bern"),
    "SE": GeoCoordinate(60.1282, 18.6435, "SE", "Stockholm"),
    "NO": GeoCoordinate(60.4720, 8.4689, "NO", "Oslo"),
    "FI": GeoCoordinate(61.9241, 25.7482, "FI", "Helsinki"),
    "ES": GeoCoordinate(40.4637, -3.7492, "ES", "Madrid"),
    "IT": GeoCoordinate(41.8719, 12.5674, "IT", "Rome"),
    "NZ": GeoCoordinate(-40.9006, 174.8860, "NZ", "Wellington"),
    "KR": GeoCoordinate(35.9078, 127.7669, "KR", "Seoul"),
    "MX": GeoCoordinate(23.6345, -102.5528, "MX", "Mexico City"),
    "ID": GeoCoordinate(-0.7893, 113.9213, "ID", "Jakarta"),
    "MY": GeoCoordinate(4.2105, 101.9758, "MY", "Kuala Lumpur"),
    "TH": GeoCoordinate(15.8700, 100.9925, "TH", "Bangkok"),
    "VN": GeoCoordinate(14.0583, 108.2772, "VN", "Hanoi"),
    "PH": GeoCoordinate(12.8797, 121.7740, "PH", "Manila"),
    "IE": GeoCoordinate(53.1424, -7.6921, "IE", "Dublin"),
    "PL": GeoCoordinate(51.9194, 19.1451, "PL", "Warsaw"),
    "IL": GeoCoordinate(31.0461, 34.8516, "IL", "Jerusalem"),
    "TR": GeoCoordinate(38.9637, 35.2433, "TR", "Ankara"),
    "SA": GeoCoordinate(23.8859, 45.0792, "SA", "Riyadh"),
    "EG": GeoCoordinate(26.8206, 30.8025, "EG", "Cairo"),
    "NG": GeoCoordinate(9.0820, 8.6753, "NG", "Abuja"),
    "KE": GeoCoordinate(-0.0236, 37.9062, "KE", "Nairobi"),
    "AR": GeoCoordinate(-38.4161, -63.6167, "AR", "Buenos Aires"),
    "CL": GeoCoordinate(-35.6751, -71.5430, "CL", "Santiago"),
    "CO": GeoCoordinate(4.5709, -74.2973, "CO", "Bogota"),
    "AT": GeoCoordinate(47.5162, 14.5501, "AT", "Vienna"),
    "BE": GeoCoordinate(50.5039, 4.4699, "BE", "Brussels"),
    "DK": GeoCoordinate(56.2639, 9.5018, "DK", "Copenhagen"),
    "CZ": GeoCoordinate(49.8175, 15.4730, "CZ", "Prague"),
    "PT": GeoCoordinate(39.3999, -8.2245, "PT", "Lisbon"),
    "GR": GeoCoordinate(39.0742, 21.8243, "GR", "Athens"),
}

# Known virtual carrier prefixes (VoIP / SMS aggregators / virtual providers)
KNOWN_VOIP_PREFIXES = {
    "+1201555", "+1800", "+1888", "+1877", "+1866", "+1855", "+1844",
    "+1900", "+1500", "+1415555", "+1650555", "+1212555"
}

# Known public cloud / hosting provider ASN IP subnets commonly used as proxies
SUSPICIOUS_PROXIES = {
    "104.28.", "104.24.", "198.41.",  # Cloudflare WARP/Relay
    "192.88.99.",  # 6to4 relay
}


@dataclass
class AnomalyScoreResult:
    risk_score: float  # 0.0 to 1.0
    risk_level: RiskLevel
    recommended_action: RecommendedAction
    anomaly_flags: List[str]
    geo_velocity_kmh: float
    distance_km: float
    time_delta_seconds: float
    carrier_assessment: str
    sim_swap_risk_score: float
    confidence_index: float
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "risk_score": round(self.risk_score, 3),
            "risk_level": self.risk_level.value,
            "recommended_action": self.recommended_action.value,
            "anomaly_flags": self.anomaly_flags,
            "geo_velocity_kmh": round(self.geo_velocity_kmh, 1),
            "distance_km": round(self.distance_km, 1),
            "time_delta_seconds": round(self.time_delta_seconds, 1),
            "carrier_assessment": self.carrier_assessment,
            "sim_swap_risk_score": round(self.sim_swap_risk_score, 3),
            "confidence_index": round(self.confidence_index, 3),
            "metadata": self.metadata,
        }


class TokenBucketLimiter:
    """Multi-tiered Token Bucket rate limiter with sliding window replenishment."""
    def __init__(self, capacity: int = 5, fill_rate_per_second: float = 0.05):
        self.capacity = capacity
        self.fill_rate = fill_rate_per_second
        self.tokens: Dict[str, float] = {}
        self.last_update: Dict[str, float] = {}

    def _replenish(self, key: str, now: float) -> None:
        if key not in self.tokens:
            self.tokens[key] = float(self.capacity)
            self.last_update[key] = now
            return

        elapsed = now - self.last_update[key]
        self.tokens[key] = min(float(self.capacity), self.tokens[key] + elapsed * self.fill_rate)
        self.last_update[key] = now

    def check_and_consume(self, key: str, cost: float = 1.0) -> Tuple[bool, float]:
        """Returns (is_allowed, remaining_tokens)"""
        now = time.time()
        self._replenish(key, now)
        if self.tokens[key] >= cost:
            self.tokens[key] -= cost
            return True, self.tokens[key]
        return False, self.tokens[key]

    def reset(self, key: str) -> None:
        if key in self.tokens:
            del self.tokens[key]
        if key in self.last_update:
            del self.last_update[key]


class GeoVelocityEngine:
    """Calculates geodesic distances and speeds to detect impossible human travel."""
    EARTH_RADIUS_KM = 6371.0
    SUPERSONIC_SPEED_THRESHOLD_KMH = 950.0  # Typical commercial airliner max cruising speed
    ORBITAL_SPEED_THRESHOLD_KMH = 2500.0   # Extreme impossible speed

    @classmethod
    def haversine_distance(cls, lat1: float, lon1: float, lat2: float, lon2: float) -> float:
        """Computes great-circle distance between two GPS coordinates in kilometers."""
        phi1 = math.radians(lat1)
        phi2 = math.radians(lat2)
        delta_phi = math.radians(lat2 - lat1)
        delta_lambda = math.radians(lon2 - lon1)

        a = math.sin(delta_phi / 2.0) ** 2 + \
            math.cos(phi1) * math.cos(phi2) * (math.sin(delta_lambda / 2.0) ** 2)
        c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))
        return cls.EARTH_RADIUS_KM * c

    @classmethod
    def resolve_coords(cls, country_code: str, fallback_lat: float = 0.0, fallback_lon: float = 0.0) -> GeoCoordinate:
        code = country_code.upper().strip()
        if code in COUNTRY_COORDINATES:
            return COUNTRY_COORDINATES[code]
        return GeoCoordinate(fallback_lat, fallback_lon, code, "Unknown")

    @classmethod
    def compute_velocity(
        cls,
        prev_country: str,
        current_country: str,
        time_elapsed_seconds: float,
        prev_lat: float = 0.0,
        prev_lon: float = 0.0,
        curr_lat: float = 0.0,
        curr_lon: float = 0.0
    ) -> Tuple[float, float]:
        """
        Calculates (distance_km, velocity_kmh).
        If same country, returns (0.0, 0.0) unless specific non-zero coords provided.
        """
        if prev_country.upper() == current_country.upper() and prev_lat == curr_lat and prev_lon == curr_lon:
            return 0.0, 0.0

        coord1 = cls.resolve_coords(prev_country, prev_lat, prev_lon)
        coord2 = cls.resolve_coords(current_country, curr_lat, curr_lon)

        distance = cls.haversine_distance(coord1.latitude, coord1.longitude, coord2.latitude, coord2.longitude)
        if time_elapsed_seconds <= 1.0:
            time_elapsed_seconds = 1.0

        hours = time_elapsed_seconds / 3600.0
        velocity = distance / hours
        return distance, velocity


class SimSwapHeuristicEngine:
    """Evaluates probability of SIM hijacking or device spoofing based on telecom metrics."""
    @classmethod
    def evaluate_phone_entropy(cls, phone_number: str) -> float:
        """Measures Shannon entropy of the digit sequence to detect synthetic patterned numbers."""
        digits = re.sub(r"\D", "", phone_number)
        if not digits:
            return 0.0
        length = len(digits)
        frequencies: Dict[str, int] = {}
        for d in digits:
            frequencies[d] = frequencies.get(d, 0) + 1

        entropy = 0.0
        for count in frequencies.values():
            p = count / length
            entropy -= p * math.log2(p)
        return entropy

    @classmethod
    def analyze_carrier_type(cls, phone_number: str, country_code: str) -> Tuple[str, float]:
        """
        Returns (carrier_assessment, risk_penalty).
        Identifies VoIP, toll-free, synthetic, or standard cellular carrier patterns.
        """
        cleaned = phone_number.strip().replace(" ", "").replace("-", "")

        # Check known VoIP / Toll-free prefixes
        for prefix in KNOWN_VOIP_PREFIXES:
            if cleaned.startswith(prefix):
                return "VOIP_VIRTUAL_AGGREGATOR", 0.35

        # Check repetitive / dummy patterns like +1111111111, +1234567890
        digits_only = re.sub(r"\D", "", cleaned)
        if len(set(digits_only)) <= 2 and len(digits_only) >= 8:
            return "SYNTHETIC_REPETITIVE_DIGITS", 0.50

        entropy = cls.evaluate_phone_entropy(cleaned)
        if entropy < 1.8 and len(digits_only) >= 10:
            return "LOW_ENTROPY_PATTERNED", 0.25

        # Standard MNO Cellular
        return "STANDARD_CELLULAR_MNO", 0.02


class AuthAnomalyDetector:
    """
    Ensemble Authentication Anomaly Detector for FocusDNS.
    Consolidates geo-velocity, carrier analysis, IP reputation, and brute-force tracking.
    """
    def __init__(self):
        self.ip_limiter = TokenBucketLimiter(capacity=8, fill_rate_per_second=0.1)     # 8 requests burst, 1 every 10s
        self.phone_limiter = TokenBucketLimiter(capacity=5, fill_rate_per_second=0.033) # 5 requests burst, 1 every 30s
        self.geo_engine = GeoVelocityEngine()
        self.sim_engine = SimSwapHeuristicEngine()
        self.historical_logins: Dict[str, Dict[str, Any]] = {}
        self.audit_trail: List[Dict[str, Any]] = []
        self.max_audit_records: int = 500

    def record_login_attempt(
        self,
        phone: str,
        ip: str,
        country: str,
        device_fingerprint: str = "",
        success: bool = True
    ) -> None:
        record = {
            "phone": phone,
            "ip": ip,
            "country": country.upper(),
            "device_fingerprint": device_fingerprint,
            "timestamp": time.time(),
            "success": success,
        }
        self.historical_logins[phone] = record
        self.audit_trail.append(record)
        if len(self.audit_trail) > self.max_audit_records:
            self.audit_trail.pop(0)

    def evaluate_request(
        self,
        phone: str,
        client_ip: str,
        country_code: str,
        device_fingerprint: str = "",
        user_agent: str = "",
        carrier_hint: str = ""
    ) -> AnomalyScoreResult:
        """
        Runs comprehensive multi-factor threat detection on incoming authentication attempt.
        """
        now = time.time()
        flags: List[str] = []
        risk_components: List[float] = []

        # 1. Rate Limiting Check (Token Bucket)
        ip_allowed, _ = self.ip_limiter.check_and_consume(client_ip)
        if not ip_allowed:
            flags.append("RATE_LIMIT_IP_EXHAUSTED")
            risk_components.append(0.40)

        phone_allowed, _ = self.phone_limiter.check_and_consume(phone)
        if not phone_allowed:
            flags.append("RATE_LIMIT_PHONE_VELOCITY")
            risk_components.append(0.50)

        # 2. Geo-Velocity / Impossible Travel Analysis
        prev_login = self.historical_logins.get(phone)
        distance_km = 0.0
        velocity_kmh = 0.0
        time_delta = 999999.0

        if prev_login:
            prev_country = prev_login.get("country", country_code)
            prev_time = prev_login.get("timestamp", now - 86400)
            time_delta = max(1.0, now - prev_time)

            distance_km, velocity_kmh = self.geo_engine.compute_velocity(
                prev_country=prev_country,
                current_country=country_code,
                time_elapsed_seconds=time_delta
            )

            if velocity_kmh > GeoVelocityEngine.ORBITAL_SPEED_THRESHOLD_KMH:
                flags.append("IMPOSSIBLE_TRAVEL_ORBITAL_VELOCITY")
                risk_components.append(0.85)
            elif velocity_kmh > GeoVelocityEngine.SUPERSONIC_SPEED_THRESHOLD_KMH:
                flags.append("IMPOSSIBLE_TRAVEL_SUPERSONIC")
                risk_components.append(0.60)
            elif distance_km > 2000 and time_delta < 7200:
                flags.append("RAPID_INTERCONTINENTAL_HOP")
                risk_components.append(0.35)

            # Device Fingerprint Divergence
            prev_dev = prev_login.get("device_fingerprint", "")
            if prev_dev and device_fingerprint and prev_dev != device_fingerprint:
                flags.append("DEVICE_FINGERPRINT_MISMATCH")
                risk_components.append(0.20)

        # 3. Carrier & SIM-Swap Heuristics
        carrier_desc, carrier_risk = self.sim_engine.analyze_carrier_type(phone, country_code)
        if carrier_risk > 0.15:
            flags.append(f"CARRIER_ANOMALY_{carrier_desc}")
            risk_components.append(carrier_risk)

        sim_swap_score = carrier_risk
        if "DEVICE_FINGERPRINT_MISMATCH" in flags and "RAPID_INTERCONTINENTAL_HOP" in flags:
            sim_swap_score += 0.40
            flags.append("CRITICAL_SIM_SWAP_SIGNATURE")

        # 4. Proxy / Suspicious IP Analysis
        for proxy_prefix in SUSPICIOUS_PROXIES:
            if client_ip.startswith(proxy_prefix):
                flags.append("ANONYMIZING_PROXY_DETECTED")
                risk_components.append(0.30)
                break

        # Calculate final aggregated risk score (bounded between 0.0 and 1.0)
        if risk_components:
            # Weighted soft-max combination
            base_risk = max(risk_components)
            additional_risk = sum(r * 0.25 for r in risk_components if r != base_risk)
            total_risk = min(1.0, base_risk + additional_risk)
        else:
            total_risk = 0.02  # Nominal baseline risk

        # Determine Risk Level & Action
        if total_risk >= 0.75:
            level = RiskLevel.CRITICAL
            action = RecommendedAction.BLOCK
        elif total_risk >= 0.50:
            level = RiskLevel.HIGH
            action = RecommendedAction.CHALLENGE
        elif total_risk >= 0.25:
            level = RiskLevel.MEDIUM
            action = RecommendedAction.DELAY
        elif total_risk >= 0.10:
            level = RiskLevel.LOW
            action = RecommendedAction.ALLOW
        else:
            level = RiskLevel.SAFE
            action = RecommendedAction.ALLOW

        confidence = 0.95 if prev_login else 0.70

        return AnomalyScoreResult(
            risk_score=total_risk,
            risk_level=level,
            recommended_action=action,
            anomaly_flags=flags,
            geo_velocity_kmh=velocity_kmh,
            distance_km=distance_km,
            time_delta_seconds=time_delta,
            carrier_assessment=carrier_desc,
            sim_swap_risk_score=min(1.0, sim_swap_score),
            confidence_index=confidence,
            metadata={
                "client_ip": client_ip,
                "country_code": country_code,
                "user_agent": user_agent[:80] if user_agent else "N/A",
                "device_fingerprint": device_fingerprint[:16] if device_fingerprint else "N/A",
                "evaluated_at": now,
            }
        )

    def get_audit_trail(self, limit: int = 50) -> List[Dict[str, Any]]:
        return self.audit_trail[-limit:]


# Global singleton instance
_anomaly_detector: Optional[AuthAnomalyDetector] = None

def get_auth_anomaly_detector() -> AuthAnomalyDetector:
    global _anomaly_detector
    if _anomaly_detector is None:
        _anomaly_detector = AuthAnomalyDetector()
    return _anomaly_detector
