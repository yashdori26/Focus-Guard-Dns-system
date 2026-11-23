import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'fleet_device_model.dart';

/// Connection state of the cross-device sync coordinator.
enum CrossDeviceSyncStatus {
  disconnected,
  connecting,
  connected,
  syncing,
  error,
}

/// Incoming synchronization event dispatched from remote fleet nodes.
@immutable
class RemoteFleetEvent {
  final String eventType;
  final String originDeviceId;
  final Map<String, dynamic> payload;
  final DateTime timestamp;

  const RemoteFleetEvent({
    required this.eventType,
    required this.originDeviceId,
    required this.payload,
    required this.timestamp,
  });

  factory RemoteFleetEvent.fromJson(Map<String, dynamic> json) {
    return RemoteFleetEvent(
      eventType: json['type'] as String? ?? 'UNKNOWN',
      originDeviceId: json['originDeviceId'] as String? ?? 'remote',
      payload: json,
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : DateTime.now(),
    );
  }
}

/// Bidirectional cross-device synchronization coordinator syncing Android,
/// browser extensions, and web admin dashboards.
class CrossDeviceSyncCoordinator {
  final String userId;
  final String localDeviceId;
  final String daemonWsUrl;

  CrossDeviceSyncStatus _status = CrossDeviceSyncStatus.disconnected;
  final List<FleetDeviceModel> _fleetDevices = [];

  final _statusController = StreamController<CrossDeviceSyncStatus>.broadcast();
  final _eventController = StreamController<RemoteFleetEvent>.broadcast();
  final _fleetController = StreamController<List<FleetDeviceModel>>.broadcast();

  Timer? _connectTimer;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  CrossDeviceSyncCoordinator({
    required this.userId,
    required this.localDeviceId,
    this.daemonWsUrl = 'ws://localhost:5354/sync',
  });

  Stream<CrossDeviceSyncStatus> get statusStream => _statusController.stream;
  Stream<RemoteFleetEvent> get eventStream => _eventController.stream;
  Stream<List<FleetDeviceModel>> get fleetStream => _fleetController.stream;

  CrossDeviceSyncStatus get status => _status;
  List<FleetDeviceModel> get fleetDevices => List.unmodifiable(_fleetDevices);

  /// Initializes synchronization connection and sets up periodic heartbeat.
  void start() {
    _mockSeedFleet();
    _connect();
    _startHeartbeat();
  }

  /// Terminates synchronization connection and disposes resources.
  void stop() {
    _connectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _setStatus(CrossDeviceSyncStatus.disconnected);
  }

  void _connect() {
    _setStatus(CrossDeviceSyncStatus.connecting);

    // Simulated connection establishment to local daemon
    _connectTimer?.cancel();
    _connectTimer = Timer(const Duration(milliseconds: 300), () {
      if (_status != CrossDeviceSyncStatus.disconnected) {
        _setStatus(CrossDeviceSyncStatus.connected);
        _reconnectAttempts = 0;
        _sendHandshake();
      }
    });
  }

  void _setStatus(CrossDeviceSyncStatus s) {
    _status = s;
    _statusController.add(_status);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_status == CrossDeviceSyncStatus.connected) {
        _dispatchHeartbeat();
      }
    });
  }

  void _sendHandshake() {
    final handshakePayload = {
      'type': 'HANDSHAKE',
      'clientType': 'FLUTTER_MOBILE',
      'userId': userId,
      'deviceId': localDeviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    // In production, sent over WebSocket
    debugPrint('[SyncCoordinator] Dispatched handshake: ${jsonEncode(handshakePayload)}');
  }

  void _dispatchHeartbeat() {
    final payload = {
      'type': 'HEARTBEAT',
      'deviceId': localDeviceId,
      'isOnline': true,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    debugPrint('[SyncCoordinator] Heartbeat pulse: ${jsonEncode(payload)}');
  }

  /// Broadcasts strict focus lock initiation to all paired fleet nodes (Browser extensions, PCs).
  void broadcastFocusLock({
    required int durationMinutes,
    required bool isStrict,
  }) {
    final payload = {
      'type': 'TRIGGER_FOCUS_LOCK',
      'durationMinutes': durationMinutes,
      'isStrict': isStrict,
      'originDeviceId': localDeviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    debugPrint('[SyncCoordinator] Broadcasted fleet lock: ${jsonEncode(payload)}');

    // Update in-memory state of fleet devices
    for (int i = 0; i < _fleetDevices.length; i++) {
      _fleetDevices[i] = _fleetDevices[i].copyWith(
        activeMode: 'focus',
        isStrictLockActive: isStrict,
        sessionRemainingSeconds: durationMinutes * 60,
      );
    }
    _fleetController.add(List.unmodifiable(_fleetDevices));
  }

  /// Broadcasts break initiation to fleet nodes.
  void broadcastBreak({int breakMinutes = 5}) {
    final payload = {
      'type': 'TRIGGER_BREAK',
      'breakMinutes': breakMinutes,
      'originDeviceId': localDeviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    debugPrint('[SyncCoordinator] Broadcasted fleet break: ${jsonEncode(payload)}');

    for (int i = 0; i < _fleetDevices.length; i++) {
      _fleetDevices[i] = _fleetDevices[i].copyWith(
        activeMode: 'break',
        sessionRemainingSeconds: breakMinutes * 60,
      );
    }
    _fleetController.add(List.unmodifiable(_fleetDevices));
  }

  /// Simulates incoming remote fleet event (e.g. from Browser extension or Web Admin).
  void simulateIncomingRemoteEvent(Map<String, dynamic> rawJson) {
    final event = RemoteFleetEvent.fromJson(rawJson);
    _eventController.add(event);

    if (event.eventType == 'TRIGGER_FOCUS_LOCK') {
      final duration = event.payload['durationMinutes'] as int? ?? 25;
      final strict = event.payload['isStrict'] as bool? ?? true;
      for (int i = 0; i < _fleetDevices.length; i++) {
        _fleetDevices[i] = _fleetDevices[i].copyWith(
          activeMode: 'focus',
          isStrictLockActive: strict,
          sessionRemainingSeconds: duration * 60,
        );
      }
      _fleetController.add(List.unmodifiable(_fleetDevices));
    }
  }

  /// Seed initial paired devices for realistic UI rendering.
  void _mockSeedFleet() {
    _fleetDevices.clear();
    _fleetDevices.addAll([
      FleetDeviceModel(
        deviceId: localDeviceId,
        deviceName: 'Pixel 8 Pro (Primary)',
        platform: FleetPlatformType.android,
        clientVersion: '2.0.0',
        lastHeartbeat: DateTime.now(),
        isOnline: true,
        activeMode: 'focus',
        isStrictLockActive: true,
        sessionRemainingSeconds: 25 * 60,
        distractionsBlockedToday: 48,
        minutesReclaimedToday: 65,
        batteryPercentage: 88,
        isCharging: false,
        pingLatencyMs: 8,
      ),
      FleetDeviceModel(
        deviceId: 'ext_chrome_work_laptop',
        deviceName: 'MacBook Air (Chrome Ext)',
        platform: FleetPlatformType.chromeExtension,
        clientVersion: '2.0.0',
        lastHeartbeat: DateTime.now().subtract(const Duration(seconds: 12)),
        isOnline: true,
        activeMode: 'focus',
        isStrictLockActive: true,
        sessionRemainingSeconds: 25 * 60,
        distractionsBlockedToday: 112,
        minutesReclaimedToday: 65,
        batteryPercentage: 94,
        isCharging: true,
        pingLatencyMs: 14,
      ),
      FleetDeviceModel(
        deviceId: 'pc_home_workstation',
        deviceName: 'Windows 11 Rig',
        platform: FleetPlatformType.windows,
        clientVersion: '1.9.8',
        lastHeartbeat: DateTime.now().subtract(const Duration(minutes: 5)),
        isOnline: false,
        activeMode: 'unrestricted',
        isStrictLockActive: false,
        sessionRemainingSeconds: 0,
        distractionsBlockedToday: 15,
        minutesReclaimedToday: 20,
        pingLatencyMs: 32,
      ),
    ]);

    _fleetController.add(List.unmodifiable(_fleetDevices));
  }

  void dispose() {
    stop();
    _statusController.close();
    _eventController.close();
    _fleetController.close();
  }
}
