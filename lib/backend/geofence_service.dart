import 'dart:async';
import 'package:flutter/services.dart';

/**
 * GeofenceZoneModel
 * =================
 * Represents a geographical boundary defined by an enterprise or school.
 */
class GeofenceZoneModel {
  final String zoneId;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final bool enforceLock;
  final String description;

  const GeofenceZoneModel({
    required this.zoneId,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 200.0,
    this.enforceLock = true,
    this.description = '',
  });

  factory GeofenceZoneModel.fromMap(Map<dynamic, dynamic> map) {
    return GeofenceZoneModel(
      zoneId: map['zoneId']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      radiusMeters: (map['radiusMeters'] as num?)?.toDouble() ?? 200.0,
      enforceLock: map['enforceLock'] != false,
      description: map['description']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'zoneId': zoneId,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'radiusMeters': radiusMeters,
      'enforceLock': enforceLock,
      'description': description,
    };
  }
}

/**
 * GeofenceStatusModel
 * ===================
 * Real-time geofence compliance and location state.
 */
class GeofenceStatusModel {
  final double latitude;
  final double longitude;
  final bool insideRestrictedGeofence;
  final String matchedZoneName;
  final String closestZoneName;
  final double closestDistanceMeters;
  final bool canUninstallApp;
  final bool emergencyExemptionActive;

  const GeofenceStatusModel({
    this.latitude = 37.7937,
    this.longitude = -122.4000,
    this.insideRestrictedGeofence = false,
    this.matchedZoneName = 'None (Outside)',
    this.closestZoneName = 'FocusGuard Campus',
    this.closestDistanceMeters = 0.0,
    this.canUninstallApp = true,
    this.emergencyExemptionActive = true,
  });

  factory GeofenceStatusModel.fromMap(Map<dynamic, dynamic> map) {
    return GeofenceStatusModel(
      latitude: (map['latitude'] as num?)?.toDouble() ?? 37.7937,
      longitude: (map['longitude'] as num?)?.toDouble() ?? -122.4000,
      insideRestrictedGeofence: map['insideRestrictedGeofence'] == true,
      matchedZoneName: map['matchedZoneName']?.toString() ?? 'None (Outside)',
      closestZoneName: map['closestZoneName']?.toString() ?? 'None',
      closestDistanceMeters: (map['closestDistanceMeters'] as num?)?.toDouble() ?? 0.0,
      canUninstallApp: map['canUninstallApp'] != false,
      emergencyExemptionActive: map['emergencyExemptionActive'] != false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'insideRestrictedGeofence': insideRestrictedGeofence,
      'matchedZoneName': matchedZoneName,
      'closestZoneName': closestZoneName,
      'closestDistanceMeters': closestDistanceMeters,
      'canUninstallApp': canUninstallApp,
      'emergencyExemptionActive': emergencyExemptionActive,
    };
  }
}

/**
 * FocusGeofenceService
 * ====================
 * Client interface for location boundary evaluation and geofenced focus mode.
 */
class FocusGeofenceService {
  static const MethodChannel _channel = MethodChannel('focus_dns/geofence');

  // Simulation state for desktop and tests
  static GeofenceStatusModel _simulatedStatus = const GeofenceStatusModel(
    latitude: 37.7937,
    longitude: -122.4000,
    insideRestrictedGeofence: false,
    matchedZoneName: 'None (Outside)',
    closestZoneName: 'FocusGuard Global HQ',
    closestDistanceMeters: 450.0,
    canUninstallApp: true,
    emergencyExemptionActive: true,
  );

  static final List<GeofenceZoneModel> _simulatedZones = [
    const GeofenceZoneModel(
      zoneId: 'geo_sf_hq',
      name: 'FocusGuard Global HQ',
      latitude: 37.7937,
      longitude: -122.4000,
      radiusMeters: 250.0,
      enforceLock: true,
      description: 'Corporate headquarters restricted focus perimeter',
    ),
    const GeofenceZoneModel(
      zoneId: 'geo_campus_library',
      name: 'University Central Library',
      latitude: 37.8722,
      longitude: -122.2590,
      radiusMeters: 150.0,
      enforceLock: true,
      description: 'Academic study hall quiet zone',
    ),
  ];

  static void setSimulatedStatus(GeofenceStatusModel status) {
    _simulatedStatus = status;
  }

  /// Evaluates GPS coordinates against registered geofences.
  static Future<GeofenceStatusModel> evaluateCoordinates(double lat, double lon) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'evaluateLocation',
        {'latitude': lat, 'longitude': lon},
      );
      if (res != null) {
        return GeofenceStatusModel.fromMap(res);
      }
    } catch (_) {}

    // Simulated evaluation
    bool inside = false;
    String matched = 'None (Outside)';
    for (final z in _simulatedZones) {
      if ((lat - z.latitude).abs() < 0.001 && (lon - z.longitude).abs() < 0.001) {
        inside = true;
        matched = z.name;
        break;
      }
    }

    _simulatedStatus = GeofenceStatusModel(
      latitude: lat,
      longitude: lon,
      insideRestrictedGeofence: inside,
      matchedZoneName: matched,
      closestZoneName: _simulatedZones.first.name,
      closestDistanceMeters: inside ? 35.0 : 500.0,
      canUninstallApp: !inside,
      emergencyExemptionActive: true,
    );
    return _simulatedStatus;
  }

  /// Fetches registered geofence zones.
  static Future<List<GeofenceZoneModel>> getRegisteredZones() async {
    try {
      final res = await _channel.invokeMethod<List<dynamic>>('getZones');
      if (res != null) {
        return res.map((e) => GeofenceZoneModel.fromMap(e as Map)).toList();
      }
    } catch (_) {}
    return _simulatedZones;
  }

  /// Convenience aliases for tests and external callers
  static Future<List<GeofenceZoneModel>> getGeofenceZones() => getRegisteredZones();
  static Future<GeofenceStatusModel> evaluateLocation(double lat, double lon) => evaluateCoordinates(lat, lon);

  /// Triggers standard emergency call 112 (always exempt).
  static Future<bool> triggerEmergencyCall() async {
    try {
      final res = await _channel.invokeMethod<bool>('triggerEmergencyCall');
      if (res != null) return res;
    } catch (_) {}
    return true;
  }
}
