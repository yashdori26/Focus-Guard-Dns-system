import '../backend/api_client.dart';
import '../models/enums.dart';
import 'settings_repository.dart';

class HttpSettingsRepository implements SettingsRepository {
  final FocusDnsApiClient _client;
  final SettingsRepository _fallback = InMemorySettingsRepository();

  HttpSettingsRepository({FocusDnsApiClient? client})
      : _client = client ?? FocusDnsApiClient();

  String _featureKey(SecurityFeature feature) {
    switch (feature) {
      case SecurityFeature.threatIntel:
        return 'threat_intel';
      case SecurityFeature.aiThreat:
        return 'ai_threat';
      case SecurityFeature.googleSafe:
        return 'google_safe';
      case SecurityFeature.cryptojacking:
        return 'cryptojacking';
      case SecurityFeature.dnsRebinding:
        return 'dns_rebinding';
      case SecurityFeature.typosquatting:
        return 'typosquatting';
      case SecurityFeature.safesearch:
        return 'safesearch';
      case SecurityFeature.youtubeRestricted:
        return 'youtube_restricted';
      default:
        return feature.name;
    }
  }

  String _privacyKey(PrivacyFeature feature) {
    switch (feature) {
      case PrivacyFeature.disguisedTrackers:
        return 'disguised_trackers';
      case PrivacyFeature.affiliateLinks:
        return 'affiliate_links';
    }
  }

  @override
  Future<bool> isProtectionOn() async {
    final profile = await _client.getProfile();
    if (profile.containsKey('is_protection_on')) {
      final val = profile['is_protection_on'] == 1 || profile['is_protection_on'] == true;
      await _fallback.setProtectionOn(val);
      return val;
    }
    return _fallback.isProtectionOn();
  }

  @override
  Future<void> setProtectionOn(bool value) async {
    await _fallback.setProtectionOn(value);
    await _client.toggleProtection(value);
  }

  @override
  Future<bool> isStrictMode() async {
    try {
      final profile = await _client.getProfile();
      if (profile.containsKey('is_strict_mode')) {
        final val = profile['is_strict_mode'] == 1 || profile['is_strict_mode'] == true;
        await _fallback.setStrictMode(val);
        return val;
      }
    } catch (_) {}
    return _fallback.isStrictMode();
  }

  @override
  Future<bool> setStrictMode(bool value, {int? durationMinutes}) async {
    await _fallback.setStrictMode(value, durationMinutes: durationMinutes);
    try {
      await _client.setStrictMode(value, durationMinutes: durationMinutes);
    } catch (_) {}
    return true;
  }

  @override
  Future<int> getStrictRemainingSeconds() async {
    try {
      final profile = await _client.getProfile();
      if (profile.containsKey('remaining_seconds')) {
        final rem = profile['remaining_seconds'];
        if (rem is int) return rem;
        if (rem is num) return rem.toInt();
      }
    } catch (_) {}
    return _fallback.getStrictRemainingSeconds();
  }

  @override
  Future<bool> getSecurityFeature(SecurityFeature feature) async {
    final settings = await _client.getSecuritySettings();
    final key = _featureKey(feature);
    if (settings.containsKey(key)) {
      final val = settings[key] ?? false;
      await _fallback.setSecurityFeature(feature, val);
      return val;
    }
    return _fallback.getSecurityFeature(feature);
  }

  @override
  Future<void> setSecurityFeature(SecurityFeature feature, bool value) async {
    await _fallback.setSecurityFeature(feature, value);
    await _client.updateSecuritySetting(_featureKey(feature), value);
  }

  @override
  Future<bool> getPrivacyFeature(PrivacyFeature feature) async {
    final settings = await _client.getPrivacySettings();
    final key = _privacyKey(feature);
    if (settings.containsKey(key)) {
      final val = settings[key] == true || settings[key] == 1;
      await _fallback.setPrivacyFeature(feature, val);
      return val;
    }
    return _fallback.getPrivacyFeature(feature);
  }

  @override
  Future<void> setPrivacyFeature(PrivacyFeature feature, bool value) async {
    await _fallback.setPrivacyFeature(feature, value);
    await _client.updatePrivacySetting(_privacyKey(feature), value);
  }
}
