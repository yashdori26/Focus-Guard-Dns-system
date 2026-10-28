"""
server/engine/geofence_engine.py
Geofenced Boundary Policy Engine for FocusDNS MDM.

Architectural Guarantees:
1. Conditional Uninstallation by Physical Location:
   - When inside a designated Focus Geofence (School, University Campus, Corporate Office):
     * Focus lock is automatically armed.
     * can_uninstall == False (Uninstallation is strictly locked to prevent student/employee evasion).
   - When device exits all restricted geofenced zones:
     * Focus lock is disarmed.
     * can_uninstall == True (Normal mode is restored, clean uninstallation permitted).
2. Life-Safety Exemption:
   - Emergency calling (911, 112, 999, 000) is NEVER affected or blocked inside any geofence.
3. High-Accuracy Geospatial Math:
   - Precise spherical Haversine distance formula with meter-level resolution.
"""

import math
import time
from typing import Dict, Any, List, Optional, Tuple


# Earth mean radius in meters
EARTH_RADIUS_METERS = 6371000.0


def haversine_distance_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculates spherical distance between two GPS coordinates in meters."""
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)

    a = (
        math.sin(delta_phi / 2.0) ** 2
        + math.cos(phi1) * math.cos(phi2) * (math.sin(delta_lambda / 2.0) ** 2)
    )
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))
    return EARTH_RADIUS_METERS * c


class GeofenceZone:
    """Defined circular geographical boundary with MDM focus policies."""

    def __init__(
        self,
        zone_id: str,
        name: str,
        latitude: float,
        longitude: float,
        radius_meters: float = 200.0,
        tenant_id: str = "default_enterprise",
        enforce_focus_lock: bool = True,
        strict_uninstall_lock: bool = True,
        description: str = "",
    ):
        self.zone_id = zone_id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius_meters = max(10.0, radius_meters)
        self.tenant_id = tenant_id
        self.enforce_focus_lock = enforce_focus_lock
        self.strict_uninstall_lock = strict_uninstall_lock
        self.description = description
        self.created_at = time.time()

    def contains_coordinate(self, lat: float, lon: float) -> Tuple[bool, float]:
        dist = haversine_distance_meters(self.latitude, self.longitude, lat, lon)
        return (dist <= self.radius_meters, dist)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "zone_id": self.zone_id,
            "name": self.name,
            "latitude": self.latitude,
            "longitude": self.longitude,
            "radius_meters": self.radius_meters,
            "tenant_id": self.tenant_id,
            "enforce_focus_lock": self.enforce_focus_lock,
            "strict_uninstall_lock": self.strict_uninstall_lock,
            "description": self.description,
            "created_at": self.created_at,
        }


class GeofenceEngine:
    """
    Evaluates device coordinates against enterprise boundaries to determine
    real-time lock state and uninstallation permission.
    """

    def __init__(self):
        self._zones: Dict[str, GeofenceZone] = {}
        self._device_locations: Dict[str, Dict[str, Any]] = {}
        self._setup_default_zones()

    def _setup_default_zones(self) -> None:
        # Default Corporate HQ zone (San Francisco Financial District)
        sf_hq = GeofenceZone(
            zone_id="geo_sf_hq",
            name="FocusGuard Global Headquarters",
            latitude=37.7937,
            longitude=-122.4000,
            radius_meters=250.0,
            tenant_id="default_enterprise",
            enforce_focus_lock=True,
            strict_uninstall_lock=True,
            description="Restricted corporate focus zone with strict uninstallation protection",
        )
        self._zones[sf_hq.zone_id] = sf_hq

        # University Campus Library Zone
        campus_lib = GeofenceZone(
            zone_id="geo_campus_library",
            name="University Central Library",
            latitude=37.8722,
            longitude=-122.2590,
            radius_meters=150.0,
            tenant_id="default_enterprise",
            enforce_focus_lock=True,
            strict_uninstall_lock=True,
            description="Study hall quiet zone with focus enforcement",
        )
        self._zones[campus_lib.zone_id] = campus_lib

    def create_or_update_zone(self, zone: GeofenceZone) -> GeofenceZone:
        self._zones[zone.zone_id] = zone
        return zone

    def get_zone(self, zone_id: str) -> Optional[GeofenceZone]:
        return self._zones.get(zone_id)

    def delete_zone(self, zone_id: str) -> bool:
        if zone_id in self._zones:
            del self._zones[zone_id]
            return True
        return False

    def list_zones(self, tenant_id: Optional[str] = None) -> List[Dict[str, Any]]:
        zones = self._zones.values()
        if tenant_id:
            zones = [z for z in zones if z.tenant_id == tenant_id]
        return [z.to_dict() for z in zones]

    def evaluate_device_location(
        self,
        device_id: str,
        latitude: float,
        longitude: float,
        tenant_id: str = "default_enterprise",
    ) -> Dict[str, Any]:
        """
        Evaluates GPS coordinates and returns geofence posture:
        - If inside any restricted zone with focus lock:
            * inside_geofence == True
            * can_uninstall == False (uninstallation strictly locked)
            * directive == "LOCK_FOCUS"
        - If outside all restricted zones:
            * inside_geofence == False
            * can_uninstall == True (normal mode, clean uninstallation 100% allowed)
            * directive == "UNLOCK_FOCUS"
        """
        matching_zones = []
        closest_distance = float("inf")
        closest_zone_name = None

        candidate_zones = [
            z for z in self._zones.values()
            if z.tenant_id == tenant_id or z.tenant_id == "default_enterprise"
        ]

        for zone in candidate_zones:
            inside, dist = zone.contains_coordinate(latitude, longitude)
            if dist < closest_distance:
                closest_distance = dist
                closest_zone_name = zone.name

            if inside:
                matching_zones.append({
                    "zone_id": zone.zone_id,
                    "zone_name": zone.name,
                    "distance_meters": round(dist, 1),
                    "enforce_focus_lock": zone.enforce_focus_lock,
                    "strict_uninstall_lock": zone.strict_uninstall_lock,
                })

        is_inside_restricted = any(z["enforce_focus_lock"] for z in matching_zones)
        can_uninstall = not is_inside_restricted

        loc_record = {
            "device_id": device_id,
            "latitude": latitude,
            "longitude": longitude,
            "inside_restricted_geofence": is_inside_restricted,
            "matching_zones": matching_zones,
            "can_uninstall": can_uninstall,
            "closest_zone_name": closest_zone_name,
            "closest_zone_distance_meters": round(closest_distance, 1) if closest_distance != float("inf") else None,
            "directive": "LOCK_FOCUS" if is_inside_restricted else "UNLOCK_FOCUS",
            "emergency_safety_law": "Emergency 911/112 dialer is 100% exempt from all geofences.",
            "timestamp": time.time(),
        }
        self._device_locations[device_id] = loc_record
        return loc_record

    def get_device_last_location(self, device_id: str) -> Optional[Dict[str, Any]]:
        return self._device_locations.get(device_id)
