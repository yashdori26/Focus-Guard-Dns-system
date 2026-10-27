import '../models/enums.dart';

abstract class SettingsRepository {
  Future<bool> isProtectionOn();
  Future<void> setProtectionOn(bool value);

  Future<bool> isStrictMode();
  Future<bool> setStrictMode(bool value, {int? durationMinutes});
  Future<int> getStrictRemainingSeconds();

  Future<bool> getSecurityFeature(SecurityFeature feature);
  Future<void> setSecurityFeature(SecurityFeature feature, bool value);

  Future<bool> getPrivacyFeature(PrivacyFeature feature);
  Future<void> setPrivacyFeature(PrivacyFeature feature, bool value);
}

class InMemorySettingsRepository implements SettingsRepository {
  bool _protection = true;
  bool _strict = false;
  int _remainingSeconds = 0;
  final Map<SecurityFeature, bool> _sec = {
    SecurityFeature.threatIntel: true,
  };
  final Map<PrivacyFeature, bool> _priv = {
    PrivacyFeature.disguisedTrackers: true,
  };

  @override
  Future<bool> isProtectionOn() async => _protection;
  @override
  Future<void> setProtectionOn(bool value) async => _protection = value;

  @override
  Future<bool> isStrictMode() async => _strict;
  @override
  Future<bool> setStrictMode(bool value, {int? durationMinutes}) async {
    _strict = value;
    _remainingSeconds = (value && durationMinutes != null) ? durationMinutes * 60 : 0;
    return true;
  }
  @override
  Future<int> getStrictRemainingSeconds() async => _remainingSeconds;

  @override
  Future<bool> getSecurityFeature(SecurityFeature feature) async => _sec[feature] ?? false;
  @override
  Future<void> setSecurityFeature(SecurityFeature feature, bool value) async => _sec[feature] = value;

  @override
  Future<bool> getPrivacyFeature(PrivacyFeature feature) async => _priv[feature] ?? false;
  @override
  Future<void> setPrivacyFeature(PrivacyFeature feature, bool value) async => _priv[feature] = value;
}
