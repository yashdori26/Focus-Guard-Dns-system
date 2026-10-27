import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/enums.dart';
import '../repositories/settings_repository.dart';
import 'protection_state.dart';

class SecurityNotifier extends StateNotifier<Map<SecurityFeature, bool>> {
  final SettingsRepository _repo;
  SecurityNotifier(this._repo) : super({}) {
    _init();
  }

  Future<void> _init() async {
    final Map<SecurityFeature, bool> initial = {};
    for (var feature in SecurityFeature.values) {
      initial[feature] = await _repo.getSecurityFeature(feature);
    }
    state = initial;
  }

  Future<void> toggle(SecurityFeature feature, bool value) async {
    await _repo.setSecurityFeature(feature, value);
    state = {...state, feature: value};
  }
}

final securityProvider =
    StateNotifierProvider<SecurityNotifier, Map<SecurityFeature, bool>>((ref) {
  return SecurityNotifier(ref.watch(settingsRepoProvider));
});
