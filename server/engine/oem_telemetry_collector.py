"""
server/engine/oem_telemetry_collector.py
Multi-OEM Evasion Telemetry & Risk Scoring Engine for FocusDNS MDM.

Collects and analyzes security evasion events across OEM vendors:
- Samsung OneUI
- Xiaomi MIUI / HyperOS
- Oppo ColorOS / RealmeUI
- Vivo OriginOS / FuntouchOS
- Huawei EMUI / HarmonyOS
- Google Pixel / Stock AOSP

Computes real-time threat scores (0-100) while logging life-safety emergency call exemptions.
"""

import time
from typing import Dict, Any, List, Optional


# Evasion Event Types
EVASION_CLEAR_STORAGE = "CLEAR_STORAGE_ATTEMPT"
EVASION_FORCE_STOP = "FORCE_STOP_ATTEMPT"
EVASION_ADMIN_DISABLE = "ADMIN_DISABLE_ATTEMPT"
EVASION_PRIVATE_DNS = "PRIVATE_DNS_BYPASS_ATTEMPT"
EVASION_TIME_ROLLBACK = "TIME_ROLLBACK_ATTEMPT"
EVASION_DEVELOPER_OPTIONS = "DEVELOPER_OPTIONS_TAMPER"
EVASION_ROOT_PROBE = "ROOT_HOOK_PROBE"
EXEMPTION_EMERGENCY_CALL = "EMERGENCY_CALL_EXEMPTION"

# Severity weights for risk computation
EVENT_WEIGHTS = {
    EVASION_CLEAR_STORAGE: 25,
    EVASION_FORCE_STOP: 20,
    EVASION_ADMIN_DISABLE: 35,
    EVASION_PRIVATE_DNS: 30,
    EVASION_TIME_ROLLBACK: 40,
    EVASION_DEVELOPER_OPTIONS: 15,
    EVASION_ROOT_PROBE: 50,
    EXEMPTION_EMERGENCY_CALL: 0,  # Life safety calls carry zero penalty
}


class OemSecurityEvent:
    def __init__(
        self,
        event_id: str,
        device_id: str,
        oem_vendor: str,
        event_type: str,
        package_name: str,
        window_title: str,
        timestamp: Optional[float] = None,
        details: Optional[Dict[str, Any]] = None,
    ):
        self.event_id = event_id
        self.device_id = device_id
        self.oem_vendor = oem_vendor
        self.event_type = event_type
        self.package_name = package_name
        self.window_title = window_title
        self.timestamp = timestamp or time.time()
        self.details = details or {}

    def to_dict(self) -> Dict[str, Any]:
        return {
            "event_id": self.event_id,
            "device_id": self.device_id,
            "oem_vendor": self.oem_vendor,
            "event_type": self.event_type,
            "package_name": self.package_name,
            "window_title": self.window_title,
            "timestamp": self.timestamp,
            "details": self.details,
            "weight": EVENT_WEIGHTS.get(self.event_type, 10),
        }


class OemTelemetryCollector:
    """
    Central telemetry ingest and risk analysis engine for FocusDNS multi-OEM fleet.
    """

    def __init__(self):
        self._events: List[OemSecurityEvent] = []
        self._device_event_map: Dict[str, List[OemSecurityEvent]] = {}
        self._device_oems: Dict[str, str] = {}

    def record_event(
        self,
        event_id: str,
        device_id: str,
        oem_vendor: str,
        event_type: str,
        package_name: str,
        window_title: str,
        details: Optional[Dict[str, Any]] = None,
        timestamp: Optional[float] = None,
    ) -> Dict[str, Any]:
        """
        Ingests an evasion attempt or emergency exemption event.
        """
        event = OemSecurityEvent(
            event_id=event_id,
            device_id=device_id,
            oem_vendor=oem_vendor,
            event_type=event_type,
            package_name=package_name,
            window_title=window_title,
            timestamp=timestamp,
            details=details,
        )

        self._events.append(event)
        if device_id not in self._device_event_map:
            self._device_event_map[device_id] = []
        self._device_event_map[device_id].append(event)
        self._device_oems[device_id] = oem_vendor

        # Keep buffer bounded
        if len(self._events) > 5000:
            removed = self._events.pop(0)
            if removed.device_id in self._device_event_map:
                dev_list = self._device_event_map[removed.device_id]
                if removed in dev_list:
                    dev_list.remove(removed)

        return event.to_dict()

    def calculate_device_risk_score(self, device_id: str, window_seconds: int = 3600) -> Dict[str, Any]:
        """
        Computes threat score (0-100) based on recent evasion attempts in the given time window.
        """
        now = time.time()
        events = self._device_event_map.get(device_id, [])
        recent_events = [e for e in events if now - e.timestamp <= window_seconds]

        raw_score = sum(EVENT_WEIGHTS.get(e.event_type, 10) for e in recent_events)
        capped_score = min(100, raw_score)

        if capped_score >= 80:
            level = "CRITICAL"
        elif capped_score >= 50:
            level = "ELEVATED"
        elif capped_score >= 20:
            level = "MODERATE"
        else:
            level = "LOW"

        return {
            "device_id": device_id,
            "oem_vendor": self._device_oems.get(device_id, "UNKNOWN"),
            "risk_score": capped_score,
            "risk_level": level,
            "recent_event_count": len(recent_events),
            "window_seconds": window_seconds,
            "event_breakdown": {
                ev_type: sum(1 for e in recent_events if e.event_type == ev_type)
                for ev_type in set(e.event_type for e in recent_events)
            },
        }

    def get_oem_distribution(self) -> Dict[str, int]:
        dist: Dict[str, int] = {}
        for oem in self._device_oems.values():
            dist[oem] = dist.get(oem, 0) + 1
        return dist

    def get_fleet_security_summary(self) -> Dict[str, Any]:
        total_devices = len(self._device_oems)
        total_events = len(self._events)

        risk_scores = [
            self.calculate_device_risk_score(dev_id)["risk_score"]
            for dev_id in self._device_oems.keys()
        ]
        avg_score = round(sum(risk_scores) / total_devices, 1) if total_devices > 0 else 0.0

        emergency_calls = sum(1 for e in self._events if e.event_type == EXEMPTION_EMERGENCY_CALL)

        return {
            "total_monitored_devices": total_devices,
            "total_security_events": total_events,
            "fleet_average_risk_score": avg_score,
            "emergency_calls_exempted": emergency_calls,
            "oem_distribution": self.get_oem_distribution(),
        }

    def get_device_events(self, device_id: str, limit: int = 50) -> List[Dict[str, Any]]:
        dev_list = self._device_event_map.get(device_id, [])
        return [e.to_dict() for e in dev_list[-limit:]]
