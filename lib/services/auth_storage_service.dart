import 'package:shared_preferences/shared_preferences.dart';

/// Secure Local Persistence Service for Phone SMS Sessions and DNS Profiles
class AuthStorageService {
  static const String _kSessionToken = 'focus_dns_auth_session_token';
  static const String _kPhoneNumber = 'focus_dns_auth_phone_number';
  static const String _kEmail = 'focus_dns_auth_email';
  static const String _kProfileId = 'focus_dns_auth_profile_id';
  static const String _kProfileName = 'focus_dns_auth_profile_name';
  static const String _kCountryCode = 'focus_dns_auth_country_code';
  static const String _kDialCode = 'focus_dns_auth_dial_code';
  static const String _kFlag = 'focus_dns_auth_flag';
  static const String _kIsLoggedIn = 'focus_dns_auth_is_logged_in';
  static const String _kIsEmailVerified = 'focus_dns_auth_is_email_verified';

  static Future<void> saveSession({
    required String token,
    String? phone,
    String? email,
    required String profileId,
    required String profileName,
    String? countryCode,
    String? dialCode,
    String? flag,
    bool? isEmailVerified,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSessionToken, token);
    if (phone != null) await prefs.setString(_kPhoneNumber, phone);
    if (email != null) await prefs.setString(_kEmail, email);
    await prefs.setString(_kProfileId, profileId);
    await prefs.setString(_kProfileName, profileName);
    if (countryCode != null) await prefs.setString(_kCountryCode, countryCode);
    if (dialCode != null) await prefs.setString(_kDialCode, dialCode);
    if (flag != null) await prefs.setString(_kFlag, flag);
    if (isEmailVerified != null) await prefs.setBool(_kIsEmailVerified, isEmailVerified);
    await prefs.setBool(_kIsLoggedIn, true);
  }

  static Future<Map<String, String?>> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool(_kIsLoggedIn) ?? false;
    final token = prefs.getString(_kSessionToken);

    if (!isLoggedIn || token == null || token.isEmpty) {
      return {'is_logged_in': 'false'};
    }

    final isEmailVerified = prefs.getBool(_kIsEmailVerified) ?? false;

    return {
      'is_logged_in': 'true',
      'token': token,
      'phone': prefs.getString(_kPhoneNumber),
      'email': prefs.getString(_kEmail),
      'profile_id': prefs.getString(_kProfileId),
      'profile_name': prefs.getString(_kProfileName),
      'country_code': prefs.getString(_kCountryCode),
      'dial_code': prefs.getString(_kDialCode),
      'flag': prefs.getString(_kFlag),
      'is_email_verified': isEmailVerified ? 'true' : 'false',
    };
  }

  static Future<void> setEmailVerified(bool verified) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIsEmailVerified, verified);
  }

  static Future<void> updateActiveProfile(String profileId, String profileName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProfileId, profileId);
    await prefs.setString(_kProfileName, profileName);
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSessionToken);
    await prefs.remove(_kPhoneNumber);
    await prefs.remove(_kEmail);
    await prefs.remove(_kProfileId);
    await prefs.remove(_kProfileName);
    await prefs.remove(_kIsEmailVerified);
    await prefs.setBool(_kIsLoggedIn, false);
  }
}
