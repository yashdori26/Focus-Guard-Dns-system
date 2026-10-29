"""
FocusDNS AI Engine - On-Device DNS Tunneling & Covert Channel Detector.

Detects data exfiltration, C2 tunneling, and covert channels over standard DNS
queries (e.g. Cobalt Strike DNS beacons, Iodine, DNSCat2, OzymanDNS, base32/hex payloads).

Key Heuristics & Metrics Evaluated Locally:
  1. Subdomain Label Shannon Entropy: Tunneling payloads exhibit unnaturally high entropy.
  2. Character Set Distribution: High density of Base32 (A-Z, 2-7), Base64 (A-Z, a-z, 0-9, +, /),
     or Hexadecimal (0-9, a-f) in subdomain labels.
  3. Label Length & Depth Variance: Abnormally long labels (e.g. 50-63 chars) and total FQDN length.
  4. Query Record Type Multipliers: Covert channels favor TXT, NULL, CNAME, and AAAA queries.
  5. Inter-Arrival Time Jitter & Velocity: Bursts of uniquely randomized subdomains per apex domain.
  6. Vowel-to-Consonant Ratio in Payloads: Purely algorithmic data encoding has low/erratic vowel ratios.

Inviolable Constraints:
  1. Life Safety Exemption: Emergency domains (911.gov, 112.gov, push.apple.com,
     update.microsoft.com, play.googleapis.com) are hardcoded EXEMPT and NEVER flagged.
  2. Conditional Whitelisting Law: Whitelist additions are permitted when idle;
     strictly forbidden and raises PermissionError("ERROR_ACCESS_DENIED (5)")
     when locked or when countdown timer > 0.
  3. 100% Local Inference: Evaluates in sub-50 microseconds with zero cloud dependencies.
"""

import time
import math
import re
import threading
from typing import Dict, List, Set, Optional, Tuple, Any

from server.ai.fast_tokenizer import FastTokenizer

# Hardcoded Life Safety Exemptions
LIFE_SAFETY_DOMAINS: Set[str] = {
    "911.gov",
    "112.gov",
    "push.apple.com",
    "update.microsoft.com",
    "play.googleapis.com"
}

# Recognized Legitimate CDNs and Dynamic DNS that naturally have long subdomains
LEGITIMATE_HIGH_ENTROPY_APEXES: Set[str] = {
    "cloudfront.net",
    "akamaiedge.net",
    "azureedge.net",
    "fastly.net",
    "googleusercontent.com",
    "trafficmanager.net",
    "githubusercontent.com"
}


class DnsTunnelingVerdict:
    """Structured verdict from DNS tunneling analysis."""
    __slots__ = (
        "domain", "is_tunneling", "risk_score", "detected_encoding",
        "subdomain_entropy", "payload_length", "qtype", "reason",
        "is_exempt", "is_whitelisted", "scan_duration_us"
    )

    def __init__(
        self,
        domain: str,
        is_tunneling: bool,
        risk_score: float,
        detected_encoding: str,
        subdomain_entropy: float,
        payload_length: int,
        qtype: str,
        reason: str,
        is_exempt: bool = False,
        is_whitelisted: bool = False,
        scan_duration_us: float = 0.0
    ):
        self.domain = domain
        self.is_tunneling = is_tunneling
        self.risk_score = round(risk_score, 2)
        self.detected_encoding = detected_encoding
        self.subdomain_entropy = round(subdomain_entropy, 4)
        self.payload_length = payload_length
        self.qtype = qtype
        self.reason = reason
        self.is_exempt = is_exempt
        self.is_whitelisted = is_whitelisted
        self.scan_duration_us = round(scan_duration_us, 2)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "domain": self.domain,
            "is_tunneling": self.is_tunneling,
            "risk_score": self.risk_score,
            "detected_encoding": self.detected_encoding,
            "subdomain_entropy": self.subdomain_entropy,
            "payload_length": self.payload_length,
            "qtype": self.qtype,
            "reason": self.reason,
            "is_exempt": self.is_exempt,
            "is_whitelisted": self.is_whitelisted,
            "scan_duration_us": self.scan_duration_us
        }


class DnsTunnelingDetector:
    """
    On-device real-time behavioral and lexical detector for DNS covert channels
    and exfiltration tunnels.
    """

    def __init__(
        self,
        risk_threshold: float = 65.0,
        history_window_seconds: int = 60,
        max_tracked_apexes: int = 5000
    ):
        self.risk_threshold = risk_threshold
        self.history_window = history_window_seconds
        self.max_tracked_apexes = max_tracked_apexes

        self._tokenizer = FastTokenizer()
        self._lock = threading.RLock()

        # Protection State & Conditional Whitelisting Law
        self._is_locked: bool = False
        self._countdown_seconds: int = 0
        self._whitelist: Set[str] = set()

        # Rolling history per apex domain: apex -> list of (timestamp, subdomain_prefix)
        self._apex_history: Dict[str, List[Tuple[float, str]]] = {}

        # Telemetry metrics
        self._total_scanned: int = 0
        self._total_tunneling_blocked: int = 0
        self._exempt_bypasses: int = 0
        self._whitelisted_bypasses: int = 0

    # --------------------------------------------------------------------------
    # Lock State & Conditional Whitelisting Law
    # --------------------------------------------------------------------------

    def set_lock_state(self, is_locked: bool, countdown_seconds: int = 0) -> None:
        """Sets protection lock and countdown timer."""
        with self._lock:
            self._is_locked = is_locked
            self._countdown_seconds = max(0, countdown_seconds)

    @property
    def is_locked(self) -> bool:
        with self._lock:
            return self._is_locked or self._countdown_seconds > 0

    def add_whitelist(self, domain: str) -> bool:
        """
        Adds domain to tunneling whitelist.
        Permitted when idle; raises PermissionError if locked.
        """
        clean = domain.lower().strip().rstrip(".")
        if not clean:
            return False

        with self._lock:
            if self.is_locked:
                raise PermissionError(
                    "ERROR_ACCESS_DENIED (5): Conditional Whitelisting Law prevents "
                    "adding whitelist entries during an active focus lock or timer."
                )
            self._whitelist.add(clean)
            return True

    def remove_whitelist(self, domain: str) -> bool:
        clean = domain.lower().strip().rstrip(".")
        with self._lock:
            if self.is_locked:
                raise PermissionError(
                    "ERROR_ACCESS_DENIED (5): Conditional Whitelisting Law prevents "
                    "removing whitelist entries during an active focus lock."
                )
            if clean in self._whitelist:
                self._whitelist.remove(clean)
                return True
            return False

    def get_whitelist(self) -> List[str]:
        with self._lock:
            return sorted(list(self._whitelist))

    # --------------------------------------------------------------------------
    # Life Safety Exemption Check
    # --------------------------------------------------------------------------

    @classmethod
    def is_life_safety_exempt(cls, domain: str) -> bool:
        """Inviolable check: emergency and platform update domains are never flagged."""
        clean = domain.lower().strip().rstrip(".")
        if clean in LIFE_SAFETY_DOMAINS:
            return True
        for exempt in LIFE_SAFETY_DOMAINS:
            if clean.endswith("." + exempt):
                return True
        return False

    # --------------------------------------------------------------------------
    # Encoding & Statistical Detection
    # --------------------------------------------------------------------------

    @classmethod
    def detect_encoding_type(cls, payload: str) -> Tuple[str, float]:
        """
        Detects if payload strongly matches Base32, Hex, or Base64 encoding.
        Returns: (encoding_name, density_ratio)
        """
        if not payload:
            return "PLAINTEXT", 0.0

        n = len(payload)
        clean = payload.lower()

        # Hex check: [0-9a-f]
        hex_matches = sum(1 for ch in clean if ch in "0123456789abcdef")
        hex_ratio = hex_matches / n

        # Base32 check: [a-z2-7]
        b32_matches = sum(1 for ch in clean if ch in "abcdefghijklmnopqrstuvwxyz234567")
        b32_ratio = b32_matches / n

        # Digit density
        digit_count = sum(1 for ch in payload if ch.isdigit())
        digit_ratio = digit_count / n

        if hex_ratio >= 0.95 and digit_ratio >= 0.20 and n >= 12:
            return "HEXADECIMAL", hex_ratio

        if b32_ratio >= 0.98 and digit_ratio >= 0.15 and n >= 16:
            return "BASE32", b32_ratio

        # Check for mixed case in original payload (Base64 signature)
        has_upper = any(c.isupper() for c in payload)
        has_lower = any(c.islower() for c in payload)
        has_digit = any(c.isdigit() for c in payload)
        if has_upper and has_lower and has_digit and n >= 16:
            return "BASE64", 0.90

        return "PLAINTEXT", 0.0

    @classmethod
    def extract_apex_and_subdomain(cls, domain: str) -> Tuple[str, str]:
        """Splits domain into (apex_domain, subdomain_prefix)."""
        clean = domain.lower().strip().rstrip(".")
        parts = clean.split(".")
        if len(parts) <= 2:
            return clean, ""
        apex = ".".join(parts[-2:])
        subdomain = ".".join(parts[:-2])
        return apex, subdomain

    # --------------------------------------------------------------------------
    # Core Evaluation Engine
    # --------------------------------------------------------------------------

    def analyze(self, domain: str, qtype: str = "A") -> DnsTunnelingVerdict:
        """
        Analyzes domain for indicators of DNS data exfiltration and tunneling.
        """
        t0 = time.perf_counter()
        clean = domain.lower().strip().rstrip(".")
        now = time.time()

        with self._lock:
            self._total_scanned += 1

            # 1. Life Safety Exemption Check (Inviolable Priority #1)
            if self.is_life_safety_exempt(clean):
                self._exempt_bypasses += 1
                duration = (time.perf_counter() - t0) * 1e6
                return DnsTunnelingVerdict(
                    domain=clean,
                    is_tunneling=False,
                    risk_score=0.0,
                    detected_encoding="EXEMPT",
                    subdomain_entropy=0.0,
                    payload_length=0,
                    qtype=qtype,
                    reason="Inviolable life-safety or critical platform infrastructure (exempt).",
                    is_exempt=True,
                    is_whitelisted=False,
                    scan_duration_us=duration
                )

            # 2. User Whitelist Check
            if clean in self._whitelist or any(clean.endswith("." + w) for w in self._whitelist):
                self._whitelisted_bypasses += 1
                duration = (time.perf_counter() - t0) * 1e6
                return DnsTunnelingVerdict(
                    domain=clean,
                    is_tunneling=False,
                    risk_score=0.0,
                    detected_encoding="WHITELISTED",
                    subdomain_entropy=0.0,
                    payload_length=0,
                    qtype=qtype,
                    reason="Domain is explicitly allowed by DNS tunneling whitelist.",
                    is_exempt=False,
                    is_whitelisted=True,
                    scan_duration_us=duration
                )

        # 3. Structural Decomposition
        apex, subdomain = self.extract_apex_and_subdomain(clean)

        # Skip known legitimate CDN providers with long hash subdomains
        if apex in LEGITIMATE_HIGH_ENTROPY_APEXES:
            duration = (time.perf_counter() - t0) * 1e6
            return DnsTunnelingVerdict(
                domain=clean,
                is_tunneling=False,
                risk_score=5.0,
                detected_encoding="LEGITIMATE_CDN",
                subdomain_entropy=0.0,
                payload_length=len(subdomain),
                qtype=qtype,
                reason="Recognized legitimate CDN infrastructure.",
                scan_duration_us=duration
            )

        if not subdomain:
            duration = (time.perf_counter() - t0) * 1e6
            return DnsTunnelingVerdict(
                domain=clean,
                is_tunneling=False,
                risk_score=0.0,
                detected_encoding="APEX_ONLY",
                subdomain_entropy=0.0,
                payload_length=0,
                qtype=qtype,
                reason="Apex domain without subdomain payload.",
                scan_duration_us=duration
            )

        # 4. Lexical Feature Scoring
        # Remove dots from subdomain to evaluate contiguous encoded chunks
        raw_payload = subdomain.replace(".", "")
        payload_len = len(raw_payload)

        # Shannon Entropy of Subdomain Payload
        entropy = self._tokenizer.shannon_entropy(raw_payload)

        # Vowel Ratio
        vowel_ratio, _, _ = self._tokenizer.vowel_consonant_ratio(raw_payload)

        # Encoding Detection
        encoding_name, encoding_density = self.detect_encoding_type(raw_payload)

        # 5. Composite Risk Score Calculation
        score = 0.0
        reasons: List[str] = []

        # A. Payload Length Factor (max 25 pts)
        if payload_len >= 50:
            score += 25.0
            reasons.append(f"Excessive payload length ({payload_len} chars)")
        elif payload_len >= 32:
            score += 18.0
            reasons.append(f"High payload length ({payload_len} chars)")
        elif payload_len >= 20:
            score += 8.0

        # B. Shannon Entropy Factor (max 30 pts)
        if entropy >= 4.2:
            score += 30.0
            reasons.append(f"Extreme payload entropy ({entropy:.2f} bits)")
        elif entropy >= 3.6:
            score += 20.0
            reasons.append(f"High payload entropy ({entropy:.2f} bits)")
        elif entropy >= 3.0:
            score += 10.0

        # C. Vowel Deficit (max 15 pts)
        # Random binary/encoded data rarely matches natural English vowel ratio (~38%)
        if payload_len >= 16:
            if vowel_ratio < 0.12 or vowel_ratio > 0.65:
                score += 15.0
                reasons.append(f"Abnormal vowel ratio ({vowel_ratio * 100:.1f}%)")

        # D. Encoding Signature (max 20 pts)
        if encoding_name in ("HEXADECIMAL", "BASE32", "BASE64"):
            score += 20.0 * encoding_density
            reasons.append(f"Detected {encoding_name} encoded data chunk")

        # E. Query Type Multiplier
        clean_qtype = qtype.upper().strip()
        if clean_qtype in ("TXT", "NULL"):
            score *= 1.30
            reasons.append(f"High-abuse query type {clean_qtype}")
        elif clean_qtype == "CNAME":
            score *= 1.15

        # 6. Velocity / Burst Correlation per Apex
        with self._lock:
            # Clean old history
            history = self._apex_history.setdefault(apex, [])
            cutoff = now - self.history_window
            history = [entry for entry in history if entry[0] >= cutoff]
            history.append((now, subdomain))
            self._apex_history[apex] = history

            # If more than 8 unique high-entropy queries sent to same apex within 60s
            unique_subdomains = len(set(s for _, s in history))
            if unique_subdomains >= 8 and payload_len >= 16:
                score += 20.0
                reasons.append(f"Rapid burst tunneling pattern ({unique_subdomains} unique subdomains/min)")

            # Bound cache size
            if len(self._apex_history) > self.max_tracked_apexes:
                self._apex_history.clear()

        final_score = min(100.0, max(0.0, score))
        is_tunneling = final_score >= self.risk_threshold

        with self._lock:
            if is_tunneling:
                self._total_tunneling_blocked += 1

        explanation = "; ".join(reasons) if reasons else "Normal domain lexical properties."
        duration = (time.perf_counter() - t0) * 1e6

        return DnsTunnelingVerdict(
            domain=clean,
            is_tunneling=is_tunneling,
            risk_score=final_score,
            detected_encoding=encoding_name,
            subdomain_entropy=entropy,
            payload_length=payload_len,
            qtype=clean_qtype,
            reason=explanation,
            is_exempt=False,
            is_whitelisted=False,
            scan_duration_us=duration
        )

    # --------------------------------------------------------------------------
    # Telemetry
    # --------------------------------------------------------------------------

    def get_telemetry(self) -> Dict[str, Any]:
        with self._lock:
            return {
                "total_scanned": self._total_scanned,
                "total_tunneling_blocked": self._total_tunneling_blocked,
                "exempt_bypasses": self._exempt_bypasses,
                "whitelisted_bypasses": self._whitelisted_bypasses,
                "is_locked": self.is_locked,
                "tracked_apexes_count": len(self._apex_history),
                "whitelist_count": len(self._whitelist)
            }
