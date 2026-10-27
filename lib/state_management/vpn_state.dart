import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/api_client.dart';
import '../backend/vpn_service.dart';

class VpnState {
  final bool isRunning;
  final bool isPreparing;
  final bool isBackendReachable;
  final String? errorMessage;
  final String dnsServerIp;
  final String serverUrl;

  const VpnState({
    this.isRunning = false,
    this.isPreparing = false,
    this.isBackendReachable = true,
    this.errorMessage,
    this.dnsServerIp = '10.254.1.2',
    this.serverUrl = 'http://10.0.2.2:8080/dns-query',
  });

  VpnState copyWith({
    bool? isRunning,
    bool? isPreparing,
    bool? isBackendReachable,
    String? errorMessage,
    String? dnsServerIp,
    String? serverUrl,
  }) {
    return VpnState(
      isRunning: isRunning ?? this.isRunning,
      isPreparing: isPreparing ?? this.isPreparing,
      isBackendReachable: isBackendReachable ?? this.isBackendReachable,
      errorMessage: errorMessage,
      dnsServerIp: dnsServerIp ?? this.dnsServerIp,
      serverUrl: serverUrl ?? this.serverUrl,
    );
  }
}

class VpnNotifier extends StateNotifier<VpnState> {
  final FocusDnsApiClient _apiClient = FocusDnsApiClient();

  VpnNotifier() : super(const VpnState()) {
    _init();
  }

  void _init() {
    checkStatus();
    FocusDnsVpnManager.registerStateListener((running, reachable) {
      state = state.copyWith(isRunning: running, isBackendReachable: reachable);
    });
  }

  Future<void> checkStatus() async {
    final running = await FocusDnsVpnManager.isRunning();
    final reachable = await FocusDnsVpnManager.isBackendReachable();
    state = state.copyWith(isRunning: running, isBackendReachable: reachable);
  }

  Future<bool> start({String? serverUrl, String? profileId, String? apiToken}) async {
    state = state.copyWith(isPreparing: true, errorMessage: null);
    try {
      String token = apiToken ?? '';
      if (token.isEmpty) {
        await _apiClient.ensureToken();
        token = _apiClient.apiKey ?? '';
      }

      final targetProfile = profileId ?? _apiClient.profileId;
      final targetUrl = serverUrl ?? state.serverUrl;

      final success = await FocusDnsVpnManager.startVpn(
        serverUrl: targetUrl,
        profileId: targetProfile,
        apiToken: token,
      );

      state = state.copyWith(
        isRunning: success,
        isPreparing: false,
        isBackendReachable: true,
        errorMessage: success ? null : 'Failed to start VPN or permission denied',
      );
      return success;
    } catch (e) {
      state = state.copyWith(
        isRunning: false,
        isPreparing: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  Future<bool> stop() async {
    state = state.copyWith(isPreparing: true, errorMessage: null);
    try {
      final success = await FocusDnsVpnManager.stopVpn();
      state = state.copyWith(
        isRunning: !success ? state.isRunning : false,
        isPreparing: false,
      );
      return success;
    } catch (e) {
      state = state.copyWith(
        isPreparing: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  Future<void> toggle({String? serverUrl, String? profileId, String? apiToken}) async {
    if (state.isRunning) {
      await stop();
    } else {
      await start(serverUrl: serverUrl, profileId: profileId, apiToken: apiToken);
    }
  }
}

final vpnProvider = StateNotifierProvider<VpnNotifier, VpnState>((ref) {
  return VpnNotifier();
});
