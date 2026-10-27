import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/enums.dart';
import '../repositories/settings_repository.dart';
import 'protection_state.dart';

class PrivacyNotifier extends StateNotifier<Map<PrivacyFeature, bool>> {
  final SettingsRepository _repo;
  PrivacyNotifier(this._repo) : super({}) {
    _init();
  }

  Future<void> _init() async {
    final Map<PrivacyFeature, bool> initial = {};
    for (var feature in PrivacyFeature.values) {
      initial[feature] = await _repo.getPrivacyFeature(feature);
    }
    state = initial;
  }

  Future<void> toggle(PrivacyFeature feature, bool value) async {
    await _repo.setPrivacyFeature(feature, value);
    state = {...state, feature: value};
  }
}

final privacyProvider =
    StateNotifierProvider<PrivacyNotifier, Map<PrivacyFeature, bool>>((ref) {
  return PrivacyNotifier(ref.watch(settingsRepoProvider));
});
