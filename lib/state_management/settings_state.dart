import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/api_client.dart';
import '../models/enums.dart';
import 'setup_state.dart';

class SettingsState {
  final String profileName;
  final String logRetention;
  final Map<Web3Feature, bool> web3;

  const SettingsState({
    required this.profileName,
    required this.logRetention,
    required this.web3,
  });

  SettingsState copyWith({
    String? profileName,
    String? logRetention,
    Map<Web3Feature, bool>? web3,
  }) {
    return SettingsState(
      profileName: profileName ?? this.profileName,
      logRetention: logRetention ?? this.logRetention,
      web3: web3 ?? this.web3,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  final FocusDnsApiClient? _client;

  SettingsNotifier({FocusDnsApiClient? client})
      : _client = client,
        super(const SettingsState(
          profileName: 'My First Profile',
          logRetention: '1 month',
          web3: {
            Web3Feature.ens: true,
            Web3Feature.unstoppable: true,
            Web3Feature.ipfs: true,
          },
        ));

  Future<void> loadSettings() async {
    final client = _client;
    if (client == null) return;
    try {
      final prof = await client.getProfile();
      if (prof['name'] != null && prof['name'].toString().isNotEmpty) {
        state = state.copyWith(
          profileName: prof['name'].toString(),
          logRetention: prof['log_retention']?.toString() ?? state.logRetention,
        );
      }
    } catch (_) {}
  }

  void updateProfileName(String name) {
    state = state.copyWith(profileName: name);
    _client?.updateProfileName(name);
  }

  void updateLogRetention(String val) {
    state = state.copyWith(logRetention: val);
    _client?.updateLogRetention(val);
  }

  void toggleWeb3(Web3Feature feature, bool val) {
    final updated = Map<Web3Feature, bool>.from(state.web3);
    updated[feature] = val;
    state = state.copyWith(web3: updated);
    _client?.updateWeb3Setting(feature.name, val);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  final client = ref.watch(apiClientProvider);
  final notifier = SettingsNotifier(client: client);
  notifier.loadSettings();
  return notifier;
});
