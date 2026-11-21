import '../models/enums.dart';
import '../services/app_storage_service.dart';
import 'settings_repository.dart';

/// A persistent implementation of [SettingsRepository] backed by [AppStorageService]
/// and local device storage. Preserves protection, timers, and security states
/// across app closures and offline restarts.
class PersistentSettingsRepository implements SettingsRepository {
  @override
  Future<bool> isProtectionOn() async {
    final val = await AppStorageService.loadProtectionState();
    return val ?? false;
  }

  @override
  Future<void> setProtectionOn(bool value) async {
    await AppStorageService.saveProtectionState(value);
  }

  @override
  Future<bool> isStrictMode() async {
    final isStrict = await AppStorageService.loadStrictMode() ?? false;
    if (!isStrict) return false;

    // Check if strict timer elapsed
    final untilMs = await AppStorageService.loadStrictUntilEpochMs();
    if (untilMs != null) {
      if (DateTime.now().millisecondsSinceEpoch >= untilMs) {
        // Expired
        await AppStorageService.saveStrictMode(false);
        await AppStorageService.saveStrictUntilEpochMs(null);
        return false;
      }
    }
    return true;
  }

  @override
  Future<bool> setStrictMode(bool value, {int? durationMinutes}) async {
    await AppStorageService.saveStrictMode(value);
    if (value && durationMinutes != null && durationMinutes > 0) {
      final untilMs = DateTime.now().add(Duration(minutes: durationMinutes)).millisecondsSinceEpoch;
      await AppStorageService.saveStrictUntilEpochMs(untilMs);
    } else if (!value) {
      await AppStorageService.saveStrictUntilEpochMs(null);
    }
    return true;
  }

  @override
  Future<int> getStrictRemainingSeconds() async {
    final untilMs = await AppStorageService.loadStrictUntilEpochMs();
    if (untilMs == null) return 0;
    final diff = untilMs - DateTime.now().millisecondsSinceEpoch;
    return diff > 0 ? (diff / 1000).ceil() : 0;
  }

  @override
  Future<bool> getSecurityFeature(SecurityFeature feature) async {
    final val = await AppStorageService.loadSecurityFeature(feature.name);
    if (val != null) return val;
    // Defaults: threatIntel enabled by default
    return feature == SecurityFeature.threatIntel;
  }

  @override
  Future<void> setSecurityFeature(SecurityFeature feature, bool value) async {
    await AppStorageService.saveSecurityFeature(feature.name, value);
  }

  @override
  Future<bool> getPrivacyFeature(PrivacyFeature feature) async {
    final val = await AppStorageService.loadPrivacyFeature(feature.name);
    if (val != null) return val;
    // Defaults: disguisedTrackers enabled by default
    return feature == PrivacyFeature.disguisedTrackers;
  }

  @override
  Future<void> setPrivacyFeature(PrivacyFeature feature, bool value) async {
    await AppStorageService.savePrivacyFeature(feature.name, value);
  }
}
