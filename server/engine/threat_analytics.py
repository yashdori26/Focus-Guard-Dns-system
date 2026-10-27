"""
FocusDNS Engine - Advanced Threat Analytics & Anomaly Detection
Features:
- Mathematical Shannon Entropy & DGA (Domain Generation Algorithms) Classifier
- DNS Tunneling & Covert Exfiltration Detection (Iodine, Cobalt Strike, DNSCat2)
- Fast-Flux & Double-Flux IP Agility Tracker (Rapid IP cycling & short TTL inspection)
- Random Subdomain Attack (PRSD / Water Torture) Detector
- Multi-dimensional Domain Risk Scoring (0 to 100 Composite Threat Score)
"""

import collections
import ipaddress
import math
import re
import threading
import time
from typing import Dict, List, Optional, Set, Tuple, Any

# Threshold Constants
ENTROPY_DGA_THRESHOLD = 3.65              # High random character dispersion
ENTROPY_EXTREME_THRESHOLD = 4.15          # Pure algorithmic / crypto randomness
TUNNELING_LABEL_LEN_THRESHOLD = 42        # Max typical subdomain label length
TUNNELING_BURST_QUERY_COUNT = 25          # Queries per minute per registered apex
FAST_FLUX_IP_DIVERSITY_THRESHOLD = 5      # Unique IPs observed for single domain within 1 hour
FAST_FLUX_MAX_TTL = 90                   # Seconds (Fast-flux networks typically use 30-60s TTL)

# Common High-Risk TLDs often abused in automated campaigns
HIGH_RISK_TLDS = {
    "xyz", "top", "buzz", "click", "rest", "surf", "monster", "cfd", "sbs",
    "country", "stream", "gq", "cf", "ml", "ga", "tk", "work", "loan", "men",
}

# Top Legitimate Domains Exemption Baseline
TOP_TRUSTED_APEX_DOMAINS = {
    "google.com", "youtube.com", "facebook.com", "amazon.com", "apple.com",
    "microsoft.com", "wikipedia.org", "twitter.com", "instagram.com", "linkedin.com",
    "netflix.com", "github.com", "cloudflare.com", "office.com", "live.com",
    "bing.com", "reddit.com", "yahoo.com", "whatsapp.com", "zoom.us",
    "spotify.com", "adobe.com", "dropbox.com", "paypal.com", "cnn.com",
    "bbc.co.uk", "medium.com", "quora.com", "vimeo.com", "twitch.tv",
    "akamai.com", "fastly.net", "cloudfront.net", "azure.com", "aws.amazon.com",
}


def calculate_shannon_entropy(label: str) -> float:
    """
    Computes mathematical Shannon Entropy: H(X) = -sum(p(x) * log2(p(x))).
    Measures degree of randomness in domain characters.
    English words typically score 1.8 - 2.8; DGA domains score 3.5 - 4.5.
    """
    if not label:
        return 0.0
    length = len(label)
    counts = collections.Counter(label)
    entropy = 0.0
    for count in counts.values():
        p = count / length
        entropy -= p * math.log2(p)
    return round(entropy, 3)


def calculate_consonant_ratio(label: str) -> float:
    """
    Calculates ratio of consonants to vowels.
    Algorithmic/DGA domains often lack vowels (e.g., 'bkxqtmnpz').
    """
    clean = re.sub(r"[^a-zA-Z]", "", label.lower())
    if not clean:
        return 0.0
    vowels = sum(1 for c in clean if c in "aeiou")
    consonants = len(clean) - vowels
    return round(consonants / len(clean), 2)


def calculate_digit_ratio(label: str) -> float:
    """Calculates ratio of numeric characters in label."""
    if not label:
        return 0.0
    digits = sum(1 for c in label if c.isdigit())
    return round(digits / len(label), 2)


def is_base64_or_hex_pattern(label: str) -> bool:
    """Checks if label exhibits characteristics of base64 or hexadecimal payload chunks."""
    if len(label) < 16:
        return False
    # Pure hex (0-9, a-f)
    if re.fullmatch(r"[0-9a-fA-F]+", label):
        return True
    # Base32 / Base64 patterns
    if re.fullmatch(r"[0-9a-zA-Z_\-]+", label) and len(label) >= 28:
        # Check high entropy + digit-letter mix
        if calculate_shannon_entropy(label) > 3.6:
            return True
    return False


class ThreatVerdict:
    """Structured result returned by the Threat Analytics Engine."""

    ALLOW = "ALLOW"
    SUSPICIOUS = "SUSPICIOUS"
    BLOCK = "BLOCK"

    def __init__(
        self,
        domain: str,
        verdict: str,
        risk_score: int,
        reasons: List[str],
        entropy: float = 0.0,
        is_tunneling: bool = False,
        is_dga: bool = False,
        is_fast_flux: bool = False,
    ):
        self.domain = domain
        self.verdict = verdict
        self.risk_score = min(100, max(0, risk_score))
        self.reasons = reasons
        self.entropy = entropy
        self.is_tunneling = is_tunneling
        self.is_dga = is_dga
        self.is_fast_flux = is_fast_flux
        self.timestamp = time.time()

    def to_dict(self) -> Dict[str, Any]:
        return {
            "domain": self.domain,
            "verdict": self.verdict,
            "risk_score": self.risk_score,
            "reasons": self.reasons,
            "entropy": self.entropy,
            "is_tunneling": self.is_tunneling,
            "is_dga": self.is_dga,
            "is_fast_flux": self.is_fast_flux,
            "timestamp": self.timestamp,
        }

    def __repr__(self) -> str:
        return f"<ThreatVerdict {self.domain} verdict={self.verdict} score={self.risk_score} reasons={self.reasons}>"


class ThreatAnalyticsEngine:
    """
    Real-time stream analytics for detecting advanced cyber threats:
    DNS Tunneling, DGA, Fast-Flux, and Water Torture floods.
    """

    def __init__(
        self,
        entropy_threshold: float = ENTROPY_DGA_THRESHOLD,
        history_window_seconds: float = 3600.0,
        max_tracked_domains: int = 10000,
    ):
        self.entropy_threshold = entropy_threshold
        self.history_window = history_window_seconds
        self.max_tracked = max_tracked_domains

        # Sliding window trackers
        # apex_domain -> list of query timestamps
        self._query_velocity: Dict[str, List[float]] = {}
        # apex_domain -> set of observed resolved IP addresses
        self._ip_history: Dict[str, Set[str]] = {}
        # apex_domain -> set of unique subdomain prefixes seen
        self._subdomain_history: Dict[str, Set[str]] = {}

        self._lock = threading.Lock()

        # Telemetry counters
        self._dga_detected = 0
        self._tunneling_detected = 0
        self._fast_flux_detected = 0
        self._total_evaluated = 0

    @staticmethod
    def extract_apex(domain: str) -> Tuple[str, str]:
        """Splits domain into (subdomain_part, apex_domain)."""
        parts = domain.strip().lower().rstrip(".").split(".")
        if len(parts) <= 2:
            return "", ".".join(parts)
        return ".".join(parts[:-2]), ".".join(parts[-2:])

    def record_resolution(self, domain: str, resolved_ips: List[str], ttl: int = 300):
        """Records resolved IP addresses to track fast-flux agility patterns."""
        if not resolved_ips or ttl > FAST_FLUX_MAX_TTL:
            return

        subdomain, apex = self.extract_apex(domain)
        target = apex or domain

        with self._lock:
            if target not in self._ip_history:
                if len(self._ip_history) >= self.max_tracked:
                    # Evict first entry
                    self._ip_history.pop(next(iter(self._ip_history)))
                self._ip_history[target] = set()
            self._ip_history[target].update(resolved_ips)

    def analyze_domain(
        self,
        domain: str,
        qtype_str: str = "A",
        client_ip: str = "127.0.0.1",
    ) -> ThreatVerdict:
        """
        Evaluates domain against all heuristic and stream-analytics classifiers.
        Computes composite risk score (0-100) and produces structured ThreatVerdict.
        """
        now = time.time()
        with self._lock:
            self._total_evaluated += 1

        clean = domain.strip().lower().rstrip(".")
        subdomain, apex = self.extract_apex(clean)
        target_apex = apex or clean

        # Whitelist fast-pass for global top trusted domains
        if target_apex in TOP_TRUSTED_APEX_DOMAINS:
            return ThreatVerdict(clean, ThreatVerdict.ALLOW, 0, ["Trusted Global Apex Domain"])

        risk_score = 0
        reasons: List[str] = []
        is_tunneling = False
        is_dga = False
        is_fast_flux = False

        # 1. Shannon Entropy Analysis on Subdomain & Registered Label
        label_to_test = subdomain.split(".")[0] if subdomain else clean.split(".")[0]
        entropy = calculate_shannon_entropy(label_to_test)
        consonant_ratio = calculate_consonant_ratio(label_to_test)
        digit_ratio = calculate_digit_ratio(label_to_test)

        if len(label_to_test) >= 10:
            if entropy >= ENTROPY_EXTREME_THRESHOLD:
                risk_score += 45
                is_dga = True
                reasons.append(f"Extreme Entropy ({entropy} > {ENTROPY_EXTREME_THRESHOLD})")
            elif entropy >= self.entropy_threshold:
                if consonant_ratio > 0.75 or digit_ratio > 0.35:
                    risk_score += 35
                    is_dga = True
                    reasons.append(f"DGA Heuristic: High Entropy ({entropy}) with unnatural character distribution")

        # 2. DNS Tunneling & Covert Exfiltration Detection
        # Heuristic A: Excessive Subdomain Label Length
        if len(subdomain) >= TUNNELING_LABEL_LEN_THRESHOLD:
            risk_score += 35
            is_tunneling = True
            reasons.append(f"Tunneling Pattern: Excessive Subdomain Length ({len(subdomain)} chars)")

        # Heuristic B: Base64 / Hex Encoded Chunks in Subdomain
        if is_base64_or_hex_pattern(label_to_test):
            risk_score += 25
            is_tunneling = True
            reasons.append("Tunneling Pattern: Hex/Base64 Encoded Subdomain Payload")

        # Heuristic C: High Velocity Subdomain Enumeration (Random Subdomain Attack / Leakage)
        with self._lock:
            # Track query velocity per apex
            if target_apex not in self._query_velocity:
                self._query_velocity[target_apex] = []
            # Purge older timestamps outside 60-second window
            vel_list = [t for t in self._query_velocity[target_apex] if now - t <= 60.0]
            vel_list.append(now)
            self._query_velocity[target_apex] = vel_list

            # Track unique subdomains per apex
            if target_apex not in self._subdomain_history:
                self._subdomain_history[target_apex] = set()
            if subdomain:
                self._subdomain_history[target_apex].add(subdomain)

            q_velocity = len(vel_list)
            unique_subs = len(self._subdomain_history[target_apex])

        if q_velocity >= TUNNELING_BURST_QUERY_COUNT and unique_subs >= 15:
            risk_score += 30
            is_tunneling = True
            reasons.append(f"Tunneling / PRSD Burst: {q_velocity} queries/min across {unique_subs} unique subdomains")

        # Heuristic D: Abnormal TXT / NULL query with high entropy
        if qtype_str in ("TXT", "NULL", "ANY") and entropy > 3.2:
            risk_score += 20
            is_tunneling = True
            reasons.append(f"Exfiltration Indicator: High-Entropy {qtype_str} Record Lookup")

        # 3. Fast-Flux & IP Agility Inspection
        with self._lock:
            observed_ips = self._ip_history.get(target_apex, set())
            unique_ip_count = len(observed_ips)

        if unique_ip_count >= FAST_FLUX_IP_DIVERSITY_THRESHOLD:
            # Check if IPs cross distinct /16 subnets
            subnets = set()
            for ip_str in observed_ips:
                try:
                    ip_obj = ipaddress.ip_address(ip_str)
                    if ip_obj.version == 4:
                        subnets.add(".".join(ip_str.split(".")[:2]))
                    else:
                        subnets.add(":".join(ip_str.split(":")[:3]))
                except ValueError:
                    pass

            if len(subnets) >= 3:
                risk_score += 35
                is_fast_flux = True
                reasons.append(f"Fast-Flux Agility: {unique_ip_count} IPs across {len(subnets)} distinct subnets")

        # 4. TLD Risk Adjustment
        tld = clean.split(".")[-1]
        if tld in HIGH_RISK_TLDS:
            risk_score += 15
            reasons.append(f"Abused TLD: .{tld}")

        # Update telemetry counters
        with self._lock:
            if is_dga:
                self._dga_detected += 1
            if is_tunneling:
                self._tunneling_detected += 1
            if is_fast_flux:
                self._fast_flux_detected += 1

        # Determine Final Verdict
        if risk_score >= 60:
            verdict = ThreatVerdict.BLOCK
        elif risk_score >= 35:
            verdict = ThreatVerdict.SUSPICIOUS
        else:
            verdict = ThreatVerdict.ALLOW

        return ThreatVerdict(
            domain=clean,
            verdict=verdict,
            risk_score=risk_score,
            reasons=reasons or ["Clean Query Profile"],
            entropy=entropy,
            is_tunneling=is_tunneling,
            is_dga=is_dga,
            is_fast_flux=is_fast_flux,
        )

    def get_stats(self) -> Dict[str, Any]:
        """Returns threat analytics metrics."""
        with self._lock:
            return {
                "total_evaluated": self._total_evaluated,
                "total_analyzed": self._total_evaluated,
                "dga_detected": self._dga_detected,
                "tunneling_detected": self._tunneling_detected,
                "fast_flux_detected": self._fast_flux_detected,
                "high_risk_blocked": self._dga_detected + self._tunneling_detected + self._fast_flux_detected,
                "tracked_velocity_domains": len(self._query_velocity),
                "tracked_ip_history_domains": len(self._ip_history),
            }

    def reset_history(self):
        """Clears all sliding window tracking state."""
        with self._lock:
            self._query_velocity.clear()
            self._ip_history.clear()
            self._subdomain_history.clear()
