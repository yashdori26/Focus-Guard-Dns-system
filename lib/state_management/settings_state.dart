import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/enums.dart';

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
  SettingsNotifier()
      : super(const SettingsState(
          profileName: 'My First Profile',
          logRetention: '1 month',
          web3: {
            Web3Feature.ens: true,
            Web3Feature.unstoppable: true,
            Web3Feature.ipfs: true,
          },
        ));

  void updateProfileName(String name) {
    state = state.copyWith(profileName: name);
  }

  void updateLogRetention(String val) {
    state = state.copyWith(logRetention: val);
  }

  void toggleWeb3(Web3Feature feature, bool val) {
    final updated = Map<Web3Feature, bool>.from(state.web3);
    updated[feature] = val;
    state = state.copyWith(web3: updated);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});
