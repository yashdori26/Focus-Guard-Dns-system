import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../backend/blocker_service.dart';

/// Secure Dual-Layer Persistence Service for Accounts, Sessions, and DNS Profiles.
/// Synchronizes across local SharedPreferences AND on-device SQLite LocalDb (focusdns.db)
/// ensuring zero data or profile loss even when the app is closed, killed, or backgrounded.
class AuthStorageService {
  static const String _kSessionToken = 'focus_dns_auth_session_token';
  static const String _kPhoneNumber = 'focus_dns_auth_phone_number';
  static const String _kEmail = 'focus_dns_auth_email';
  static const String _kPassword = 'focus_dns_auth_password';
  static const String _kRememberMe = 'focus_dns_auth_remember_me';
  static const String _kProfileId = 'focus_dns_auth_profile_id';
  static const String _kProfileName = 'focus_dns_auth_profile_name';
  static const String _kCountryCode = 'focus_dns_auth_country_code';
  static const String _kDialCode = 'focus_dns_auth_dial_code';
  static const String _kFlag = 'focus_dns_auth_flag';
  static const String _kIsLoggedIn = 'focus_dns_auth_is_logged_in';
  static const String _kIsEmailVerified = 'focus_dns_auth_is_email_verified';

  static const String _kCustomProfiles = 'focus_dns_custom_profiles';

  /// Saves the active authenticated session across SharedPreferences & SQLite LocalDb
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

    // Synchronize to native SQLite LocalDb table kv
    try {
      await FocusDnsBlockerManager.putKv(_kSessionToken, token);
      await FocusDnsBlockerManager.putKv(_kProfileId, profileId);
      await FocusDnsBlockerManager.putKv(_kProfileName, profileName);
      await FocusDnsBlockerManager.putKv(_kIsLoggedIn, 'true');
      if (email != null && email.isNotEmpty) {
        await FocusDnsBlockerManager.putKv(_kEmail, email);
      }
    } catch (e) {
      debugPrint('[AuthStorageService] Error syncing session to SQLite LocalDb: $e');
    }
  }

  /// Saves account credentials securely to local database & SharedPreferences for auto-remember
  static Future<void> saveCredentials({
    required String email,
    required String password,
    required String profileName,
    bool rememberMe = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kEmail, email);
    await prefs.setString(_kPassword, password);
    await prefs.setString(_kProfileName, profileName);
    await prefs.setBool(_kRememberMe, rememberMe);
    await prefs.setBool(_kIsLoggedIn, true);

    // Save into on-device SQLite database table kv
    try {
      await FocusDnsBlockerManager.putKv(_kEmail, email);
      await FocusDnsBlockerManager.putKv(_kPassword, password);
      await FocusDnsBlockerManager.putKv(_kProfileName, profileName);
      await FocusDnsBlockerManager.putKv(_kRememberMe, rememberMe ? 'true' : 'false');
      await FocusDnsBlockerManager.putKv(_kIsLoggedIn, 'true');
    } catch (e) {
      debugPrint('[AuthStorageService] Error saving credentials to SQLite LocalDb: $e');
    }
  }

  /// Retrieves saved credentials for pre-filling login form (falls back to SQLite LocalDb)
  static Future<Map<String, String?>> getSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    String? email = prefs.getString(_kEmail);
    String? password = prefs.getString(_kPassword);
    String? profileName = prefs.getString(_kProfileName);
    bool? rememberMe = prefs.getBool(_kRememberMe);

    // If SharedPreferences has empty values, check native SQLite LocalDb
    if (email == null || email.isEmpty) {
      try {
        final dbEmail = await FocusDnsBlockerManager.getKv(_kEmail, '');
        if (dbEmail.isNotEmpty) {
          email = dbEmail;
          await prefs.setString(_kEmail, dbEmail);
        }
      } catch (_) {}
    }

    if (password == null || password.isEmpty) {
      try {
        final dbPassword = await FocusDnsBlockerManager.getKv(_kPassword, '');
        if (dbPassword.isNotEmpty) {
          password = dbPassword;
          await prefs.setString(_kPassword, dbPassword);
        }
      } catch (_) {}
    }

    if (profileName == null || profileName.isEmpty) {
      try {
        final dbProfileName = await FocusDnsBlockerManager.getKv(_kProfileName, '');
        if (dbProfileName.isNotEmpty) {
          profileName = dbProfileName;
          await prefs.setString(_kProfileName, dbProfileName);
        }
      } catch (_) {}
    }

    if (rememberMe == null) {
      try {
        final dbRememberMe = await FocusDnsBlockerManager.getKv(_kRememberMe, 'true');
        rememberMe = (dbRememberMe != 'false');
        await prefs.setBool(_kRememberMe, rememberMe);
      } catch (_) {
        rememberMe = true;
      }
    }

    return {
      'email': email,
      'password': password,
      'profile_name': profileName,
      'remember_me': rememberMe ? 'true' : 'false',
    };
  }

  /// Returns whether user is marked as logged in
  static Future<bool> isUserLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool(_kIsLoggedIn);
    if (loggedIn != null) return loggedIn;

    try {
      final dbVal = await FocusDnsBlockerManager.getKv(_kIsLoggedIn, 'false');
      return dbVal == 'true';
    } catch (_) {
      return false;
    }
  }

  static Future<String> getActiveProfileName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_kProfileName);
    if (name != null && name.isNotEmpty) return name;

    try {
      final dbName = await FocusDnsBlockerManager.getKv(_kProfileName, '');
      if (dbName.isNotEmpty) {
        await prefs.setString(_kProfileName, dbName);
        return dbName;
      }
    } catch (_) {}

    return 'Personal Shield';
  }

  static Future<String> getActiveProfileId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_kProfileId);
    if (id != null && id.isNotEmpty) return id;

    try {
      final dbId = await FocusDnsBlockerManager.getKv(_kProfileId, '');
      if (dbId.isNotEmpty) {
        await prefs.setString(_kProfileId, dbId);
        return dbId;
      }
    } catch (_) {}

    return 'local';
  }

  static Future<Map<String, String?>> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    bool isLoggedIn = prefs.getBool(_kIsLoggedIn) ?? false;
    String? token = prefs.getString(_kSessionToken);
    String profileId = prefs.getString(_kProfileId) ?? 'local';
    String profileName = prefs.getString(_kProfileName) ?? 'Personal Shield';

    // Fall back to SQLite LocalDb if SharedPreferences is unpopulated
    if (!isLoggedIn || token == null || token.isEmpty) {
      try {
        final dbLoggedIn = await FocusDnsBlockerManager.getKv(_kIsLoggedIn, 'false');
        if (dbLoggedIn == 'true') {
          isLoggedIn = true;
          await prefs.setBool(_kIsLoggedIn, true);
        }
        final dbToken = await FocusDnsBlockerManager.getKv(_kSessionToken, '');
        if (dbToken.isNotEmpty) {
          token = dbToken;
          await prefs.setString(_kSessionToken, dbToken);
        }
        final dbPid = await FocusDnsBlockerManager.getKv(_kProfileId, '');
        if (dbPid.isNotEmpty) {
          profileId = dbPid;
          await prefs.setString(_kProfileId, dbPid);
        }
        final dbPname = await FocusDnsBlockerManager.getKv(_kProfileName, '');
        if (dbPname.isNotEmpty) {
          profileName = dbPname;
          await prefs.setString(_kProfileName, dbPname);
        }
      } catch (_) {}
    }

    if (!isLoggedIn) {
      return {
        'is_logged_in': 'false',
        'profile_id': profileId,
        'profile_name': profileName,
      };
    }

    final isEmailVerified = prefs.getBool(_kIsEmailVerified) ?? false;

    return {
      'is_logged_in': 'true',
      'token': token ?? 'local_session_active',
      'phone': prefs.getString(_kPhoneNumber),
      'email': prefs.getString(_kEmail),
      'profile_id': profileId,
      'profile_name': profileName,
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

    // Sync to SQLite LocalDb
    try {
      await FocusDnsBlockerManager.putKv(_kProfileId, profileId);
      await FocusDnsBlockerManager.putKv(_kProfileName, profileName);
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCustomProfiles);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List<dynamic> list = List<dynamic>.from(prefs.getStringList(_kCustomProfiles) ?? []);
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> deleteProfile(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString(_kProfileId);
    if (current == profileId) {
      await prefs.remove(_kProfileId);
      await prefs.setString(_kProfileName, 'Local Shield');
      try {
        await FocusDnsBlockerManager.putKv(_kProfileName, 'Local Shield');
      } catch (_) {}
    }
  }

  static Future<void> clearAllProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kProfileId);
    await prefs.remove(_kProfileName);
    await prefs.remove(_kCustomProfiles);
    await prefs.remove('focusdns_active_profile_id');
    await prefs.remove('focusdns_custom_server_url');
    await prefs.setString(_kProfileName, 'Local Shield');
    try {
      await FocusDnsBlockerManager.putKv(_kProfileName, 'Local Shield');
    } catch (_) {}
  }

  /// Clears active login session. If [preserveSavedCredentials] is true,
  /// email, profile name, and password are kept for seamless re-login.
  static Future<void> clearSession({bool preserveSavedCredentials = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSessionToken);
    await prefs.setBool(_kIsLoggedIn, false);
    await prefs.remove(_kIsEmailVerified);

    try {
      await FocusDnsBlockerManager.putKv(_kSessionToken, '');
      await FocusDnsBlockerManager.putKv(_kIsLoggedIn, 'false');
    } catch (_) {}

    if (!preserveSavedCredentials) {
      await prefs.remove(_kPhoneNumber);
      await prefs.remove(_kEmail);
      await prefs.remove(_kPassword);
      await prefs.remove(_kProfileId);
      await prefs.remove(_kProfileName);
      await prefs.remove(_kCustomProfiles);
      try {
        await FocusDnsBlockerManager.putKv(_kEmail, '');
        await FocusDnsBlockerManager.putKv(_kPassword, '');
      } catch (_) {}
    }
  }
}
