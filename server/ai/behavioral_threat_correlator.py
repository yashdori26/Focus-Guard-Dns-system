"""
FocusDNS AI Engine - Behavioral Temporal Threat Correlator & Kill-Chain Linker.

Performs real-time temporal sequence modeling and graph correlation across
DNS query streams per client device to detect multi-stage attack campaigns:
  1. Reconnaissance / Homograph Probing: Repeated queries for lookalike brand variants.
  2. DGA Scanning / C2 Beaconing: Bursts of pseudo-random domains with high NXDOMAIN ratios.
  3. Slow-and-Low Periodic Heartbeats: Fixed-interval beaconing with low jitter (Cobalt Strike).
  4. DNS Water-Torture / Random Subdomain DDoS: High-volume randomized subdomain floods.
  5. Exfiltration Chaining: Covert channel exfiltration following C2 beacon establishment.

Inviolable Constraints:
  1. Life Safety Exemption: Emergency services (911.gov, 112.gov, push.apple.com,
     update.microsoft.com, play.googleapis.com) are hardcoded EXEMPT and never scored as threats.
  2. Conditional Whitelisting Law: Whitelist additions are permitted when idle;
     strictly forbidden and raises PermissionError("ERROR_ACCESS_DENIED (5)")
     when locked or when countdown timer > 0.
  3. 100% On-Device: Sliding window state maintained in-memory with sub-30µs evaluation.
"""

import time
import math
import threading
from typing import Dict, List, Set, Optional, Tuple, Any

# Hardcoded Life Safety Exemptions
LIFE_SAFETY_DOMAINS: Set[str] = {
    "911.gov",
    "112.gov",
    "push.apple.com",
    "update.microsoft.com",
    "play.googleapis.com"
}

# Cyber Kill Chain Stages
STAGE_BENIGN = "CLEAN"
STAGE_RECON = "RECONNAISSANCE"
STAGE_DELIVERY = "PHISHING_DELIVERY"
STAGE_C2 = "COMMAND_AND_CONTROL"
STAGE_EXFILTRATION = "DATA_EXFILTRATION"


class ClientQueryRecord:
    """Represents a timestamped DNS event in a client's sliding window."""
    __slots__ = ("domain", "rcode", "qtype", "risk_score", "threat_type", "timestamp")

    def __init__(
        self,
        domain: str,
        rcode: str = "NOERROR",
        qtype: str = "A",
        risk_score: float = 0.0,
        threat_type: str = "NONE",
        timestamp: Optional[float] = None
    ):
        self.domain = domain.lower().strip()
        self.rcode = rcode.upper().strip()
        self.qtype = qtype.upper().strip()
        self.risk_score = risk_score
        self.threat_type = threat_type
        self.timestamp = timestamp or time.time()


class HostThreatPosture:
    """Real-time compromise assessment for a specific host device."""
    __slots__ = (
        "client_ip", "compromise_index", "kill_chain_stage", "active_threats_count",
        "nxdomain_rate", "beacon_period_seconds", "beacon_jitter", "quarantine_recommended",
        "primary_indicator", "evaluated_queries_count", "timestamp"
    )

    def __init__(
        self,
        client_ip: str,
        compromise_index: float,
        kill_chain_stage: str,
        active_threats_count: int,
        nxdomain_rate: float,
        beacon_period_seconds: Optional[float],
        beacon_jitter: Optional[float],
        quarantine_recommended: bool,
        primary_indicator: str,
        evaluated_queries_count: int,
        timestamp: Optional[float] = None
    ):
        self.client_ip = client_ip
        self.compromise_index = round(compromise_index, 2)
        self.kill_chain_stage = kill_chain_stage
        self.active_threats_count = active_threats_count
        self.nxdomain_rate = round(nxdomain_rate, 4)
        self.beacon_period_seconds = round(beacon_period_seconds, 2) if beacon_period_seconds is not None else None
        self.beacon_jitter = round(beacon_jitter, 4) if beacon_jitter is not None else None
        self.quarantine_recommended = quarantine_recommended
        self.primary_indicator = primary_indicator
        self.evaluated_queries_count = evaluated_queries_count
        self.timestamp = timestamp or time.time()

    def to_dict(self) -> Dict[str, Any]:
        return {
            "client_ip": self.client_ip,
            "compromise_index": self.compromise_index,
            "kill_chain_stage": self.kill_chain_stage,
            "active_threats_count": self.active_threats_count,
            "nxdomain_rate": self.nxdomain_rate,
            "beacon_period_seconds": self.beacon_period_seconds,
            "beacon_jitter": self.beacon_jitter,
            "quarantine_recommended": self.quarantine_recommended,
            "primary_indicator": self.primary_indicator,
            "evaluated_queries_count": self.evaluated_queries_count,
            "timestamp": self.timestamp
        }


class BehavioralThreatCorrelator:
    """
    Correlates temporal query sequences across local client devices to detect
    algorithmic malware campaigns, periodic C2 beaconing, and automated exfiltration.
    """

    def __init__(
        self,
        window_seconds: int = 120,
        quarantine_threshold: float = 75.0,
        max_clients_tracked: int = 2000
    ):
        self.window_seconds = window_seconds
        self.quarantine_threshold = quarantine_threshold
        self.max_clients_tracked = max_clients_tracked

        self._lock = threading.RLock()

        # Protection State & Conditional Whitelisting Law
        self._is_locked: bool = False
        self._countdown_seconds: int = 0
        self._whitelist: Set[str] = set()

        # Sliding temporal buffer per client: client_ip -> list of ClientQueryRecord
        self._client_windows: Dict[str, List[ClientQueryRecord]] = {}

        # Telemetry metrics
        self._total_correlated_events: int = 0
        self._compromise_alerts_raised: int = 0
        self._quarantines_recommended: int = 0

    # --------------------------------------------------------------------------
    # Lock State & Conditional Whitelisting Law
    # --------------------------------------------------------------------------

    def set_lock_state(self, is_locked: bool, countdown_seconds: int = 0) -> None:
        with self._lock:
            self._is_locked = is_locked
            self._countdown_seconds = max(0, countdown_seconds)

    @property
    def is_locked(self) -> bool:
        with self._lock:
            return self._is_locked or self._countdown_seconds > 0

    def add_whitelist(self, domain: str) -> bool:
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
        clean = domain.lower().strip().rstrip(".")
        if clean in LIFE_SAFETY_DOMAINS:
            return True
        for exempt in LIFE_SAFETY_DOMAINS:
            if clean.endswith("." + exempt):
                return True
        return False

    # --------------------------------------------------------------------------
    # Record Query & Correlate Behavior
    # --------------------------------------------------------------------------

    def record_query(
        self,
        client_ip: str,
        domain: str,
        rcode: str = "NOERROR",
        qtype: str = "A",
        risk_score: float = 0.0,
        threat_type: str = "NONE",
        timestamp: Optional[float] = None
    ) -> HostThreatPosture:
        """
        Ingests a query event for client_ip, updates sliding time window,
        and re-evaluates behavioral compromise posture.
        """
        clean_ip = client_ip.strip()
        clean_domain = domain.lower().strip().rstrip(".")
        now = timestamp if timestamp is not None else time.time()

        with self._lock:
            self._total_correlated_events += 1

            # Ignore life-safety and whitelisted domains in threat scoring
            if self.is_life_safety_exempt(clean_domain):
                risk_score = 0.0
                threat_type = "EXEMPT"
            elif clean_domain in self._whitelist or any(clean_domain.endswith("." + w) for w in self._whitelist):
                risk_score = 0.0
                threat_type = "WHITELISTED"

            # 1. Update sliding window
            records = self._client_windows.setdefault(clean_ip, [])
            cutoff = now - self.window_seconds
            records = [r for r in records if r.timestamp >= cutoff]

            record = ClientQueryRecord(
                domain=clean_domain,
                rcode=rcode,
                qtype=qtype,
                risk_score=risk_score,
                threat_type=threat_type,
                timestamp=now
            )
            records.append(record)
            self._client_windows[clean_ip] = records

            # Bounded capacity
            if len(self._client_windows) > self.max_clients_tracked:
                self._client_windows.clear()

            # 2. Correlate Behavioral Indicators
            posture = self._compute_posture(clean_ip, records, now)
            if posture.compromise_index >= 50.0:
                self._compromise_alerts_raised += 1
            if posture.quarantine_recommended:
                self._quarantines_recommended += 1

            return posture

    def _compute_posture(
        self,
        client_ip: str,
        records: List[ClientQueryRecord],
        now: float
    ) -> HostThreatPosture:
        """Analyzes window records to compute composite compromise index and kill-chain stage."""
        total_queries = len(records)
        if total_queries == 0:
            return HostThreatPosture(
                client_ip=client_ip,
                compromise_index=0.0,
                kill_chain_stage=STAGE_BENIGN,
                active_threats_count=0,
                nxdomain_rate=0.0,
                beacon_period_seconds=None,
                beacon_jitter=None,
                quarantine_recommended=False,
                primary_indicator="Idle clean traffic.",
                evaluated_queries_count=0,
                timestamp=now
            )

        # 1. Count threat types and NXDOMAIN errors
        threat_count = sum(1 for r in records if r.risk_score >= 60.0)
        nxdomain_count = sum(1 for r in records if r.rcode == "NXDOMAIN")
        nxdomain_rate = nxdomain_count / float(total_queries)

        # 2. Check for Periodic C2 Beaconing (Interval Regularity & Low Jitter)
        beacon_period, beacon_jitter = self._detect_beaconing(records)

        # 3. Detect Water-Torture / High-Volume Subdomain Storms
        unique_domains = len(set(r.domain for r in records))
        is_water_torture = (total_queries >= 25 and (unique_domains / total_queries) >= 0.85 and nxdomain_rate >= 0.50)

        # 4. Determine Kill-Chain Stage & Composite Compromise Score
        compromise_score = 0.0
        stage = STAGE_BENIGN
        indicators: List[str] = []

        # A. High threat query accumulation
        if threat_count >= 5:
            compromise_score += 45.0
            indicators.append(f"{threat_count} high-confidence threat queries in window")
        elif threat_count >= 2:
            compromise_score += 25.0
            indicators.append(f"{threat_count} threat queries in window")

        # B. Excessive NXDOMAIN scanning rate (DGA C2 hunt signature)
        if nxdomain_rate >= 0.50 and total_queries >= 10:
            compromise_score += 30.0
            indicators.append(f"High NXDOMAIN failure rate ({nxdomain_rate * 100:.1f}%)")
            stage = STAGE_C2

        # C. Periodic C2 Beaconing Detected
        if beacon_period and beacon_jitter is not None and beacon_jitter <= 0.15:
            compromise_score += 35.0
            indicators.append(f"C2 heartbeat beaconing detected (period: {beacon_period:.1f}s, jitter: {beacon_jitter * 100:.1f}%)")
            stage = STAGE_C2

        # D. Water Torture Storm
        if is_water_torture:
            compromise_score += 40.0
            indicators.append("Automated random subdomain flood attack")
            stage = STAGE_RECON

        # E. Exfiltration Indicator
        exfil_count = sum(1 for r in records if "EXFIL" in r.threat_type or "TUNNEL" in r.threat_type)
        if exfil_count >= 2:
            compromise_score += 40.0
            indicators.append("Covert channel data exfiltration observed")
            stage = STAGE_EXFILTRATION

        # Cap score
        final_compromise = min(100.0, max(0.0, compromise_score))
        if final_compromise < 30.0:
            stage = STAGE_BENIGN

        quarantine_rec = final_compromise >= self.quarantine_threshold
        explanation = "; ".join(indicators) if indicators else "Normal client network activity."

        return HostThreatPosture(
            client_ip=client_ip,
            compromise_index=final_compromise,
            kill_chain_stage=stage,
            active_threats_count=threat_count,
            nxdomain_rate=nxdomain_rate,
            beacon_period_seconds=beacon_period,
            beacon_jitter=beacon_jitter,
            quarantine_recommended=quarantine_rec,
            primary_indicator=explanation,
            evaluated_queries_count=total_queries,
            timestamp=now
        )

    @classmethod
    def _detect_beaconing(cls, records: List[ClientQueryRecord]) -> Tuple[Optional[float], Optional[float]]:
        """
        Analyzes inter-arrival time deltas between queries to detect low-jitter
        periodic command-and-control beacons.
        """
        if len(records) < 5:
            return None, None

        # Sort chronologically
        timestamps = sorted([r.timestamp for r in records])
        deltas = [timestamps[i] - timestamps[i - 1] for i in range(1, len(timestamps))]

        # Filter out simultaneous queries (deltas < 0.2s)
        spaced_deltas = [d for d in deltas if d >= 0.5]
        if len(spaced_deltas) < 4:
            return None, None

        mean_delta = sum(spaced_deltas) / len(spaced_deltas)
        if mean_delta < 2.0 or mean_delta > 300.0:
            return None, None

        # Calculate standard deviation & coefficient of variation (jitter)
        variance = sum((d - mean_delta) ** 2 for d in spaced_deltas) / len(spaced_deltas)
        std_dev = math.sqrt(variance)
        jitter = std_dev / mean_delta

        if jitter <= 0.20:
            return mean_delta, jitter

        return None, None

    # --------------------------------------------------------------------------
    # Telemetry
    # --------------------------------------------------------------------------

    def get_telemetry(self) -> Dict[str, Any]:
        with self._lock:
            return {
                "total_correlated_events": self._total_correlated_events,
                "compromise_alerts_raised": self._compromise_alerts_raised,
                "quarantines_recommended": self._quarantines_recommended,
                "tracked_clients_count": len(self._client_windows),
                "is_locked": self.is_locked,
                "whitelist_count": len(self._whitelist)
            }
