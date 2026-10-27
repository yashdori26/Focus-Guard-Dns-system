import 'dart:convert';
import 'package:http/http.dart' as http;

class FocusDnsApiClient {
  String baseUrl;
  String profileId;
  String? apiKey;

  FocusDnsApiClient({
    this.baseUrl = 'http://127.0.0.1:8080',
    this.profileId = 'a1b2c3',
    this.apiKey,
  });

  void updateConfig({String? newBaseUrl, String? newProfileId}) {
    if (newBaseUrl != null && newBaseUrl.isNotEmpty) {
      var url = newBaseUrl.trim();
      if (url.endsWith('/')) url = url.substring(0, url.length - 1);
      if (url.endsWith('/dns-query')) url = url.replaceAll('/dns-query', '');
      baseUrl = url;
      apiKey = null; // Re-authenticate with new host
    }
    if (newProfileId != null && newProfileId.isNotEmpty) {
      profileId = newProfileId.trim();
    }
  }

  Uri _uri(String path, [Map<String, String>? params]) {
    final queryParams = {'profile_id': profileId, ...?params};
    return Uri.parse('$baseUrl$path').replace(queryParameters: queryParams);
  }

  Future<void> ensureToken() async {
    if (apiKey != null && apiKey!.isNotEmpty) return;
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/auth/token')).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['token'] != null) {
          apiKey = data['token'];
        }
      }
    } catch (_) {}
  }

  Map<String, String> _headers() {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (apiKey != null && apiKey!.isNotEmpty) {
      h['X-Api-Key'] = apiKey!;
    }
    return h;
  }

  // --- Home / Protection ---
  Future<Map<String, dynamic>> getProfile() async {
    await ensureToken();
    try {
      final res = await http.get(_uri('/api/profile'), headers: _headers()).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        return json.decode(res.body)['profile'] ?? {};
      }
    } catch (_) {}
    return {};
  }

  Future<bool> toggleProtection(bool isOn, ) async {
    await ensureToken();
    try {
      final res = await http.post(
        _uri('/api/profile/toggle-protection'),
        headers: _headers(),
        body: json.encode({'profile_id': profileId, 'is_on': isOn}),
      ).timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setStrictMode(bool isStrict, {int? durationMinutes}) async {
    await ensureToken();
    try {
      final bodyMap = <String, dynamic>{
        'profile_id': profileId,
        'is_strict': isStrict,
      };
      if (durationMinutes != null && durationMinutes > 0) {
        bodyMap['duration_minutes'] = durationMinutes;
      }
      final res = await http.post(
        _uri('/api/profile/strict-mode'),
        headers: _headers(),
        body: json.encode(bodyMap),
      ).timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // --- Security ---
  Future<Map<String, bool>> getSecuritySettings() async {
    await ensureToken();
    try {
      final res = await http.get(_uri('/api/security'), headers: _headers()).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final sec = json.decode(res.body)['security'] as Map<String, dynamic>;
        return sec.map((k, v) => MapEntry(k, v as bool));
      }
    } catch (_) {}
    return {};
  }

  Future<void> updateSecuritySetting(String feature, bool value) async {
    await ensureToken();
    try {
      await http.patch(
        _uri('/api/security'),
        headers: _headers(),
        body: json.encode({'profile_id': profileId, 'feature': feature, 'value': value}),
      ).timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  // --- Privacy ---
  Future<Map<String, dynamic>> getPrivacySettings() async {
    await ensureToken();
    try {
      final res = await http.get(_uri('/api/privacy'), headers: _headers()).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        return json.decode(res.body)['privacy'] ?? {};
      }
    } catch (_) {}
    return {};
  }

  Future<void> updatePrivacySetting(String feature, bool value) async {
    await ensureToken();
    try {
      await http.patch(
        _uri('/api/privacy'),
        headers: _headers(),
        body: json.encode({'profile_id': profileId, 'feature': feature, 'value': value}),
      ).timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  // --- Setup & Network IP Discovery ---
  Future<Map<String, dynamic>> getSetupDetails() async {
    await ensureToken();
    try {
      final res = await http.get(_uri('/api/setup'), headers: _headers()).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
    } catch (_) {}
    return {};
  }

  Future<String?> detectClientIp() async {
    // 1. Check local backend /api/ip first
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/ip')).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data is Map && data['ip'] != null && data['ip'].toString().isNotEmpty) {
          return data['ip'].toString().trim();
        }
      }
    } catch (_) {}

    // 2. Fallback to public IP echo endpoints
    for (final url in [
      'https://api.ipify.org?format=json',
      'https://api64.ipify.org?format=json',
      'https://icanhazip.com',
    ]) {
      try {
        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 2));
        if (res.statusCode == 200) {
          if (url.contains('json')) {
            final data = json.decode(res.body);
            if (data is Map && data['ip'] != null) {
              return data['ip'].toString().trim();
            }
          } else {
            final raw = res.body.trim();
            if (raw.isNotEmpty) return raw;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  Future<String?> linkIp([String? ip]) async {
    await ensureToken();
    try {
      final body = <String, dynamic>{'profile_id': profileId};
      if (ip != null && ip.trim().isNotEmpty) {
        body['ip'] = ip.trim();
      }
      final res = await http.post(
        _uri('/api/setup/link-ip'),
        headers: _headers(),
        body: json.encode(body),
      ).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data is Map && data['linked_ip'] != null) {
          return data['linked_ip'].toString();
        }
      }
    } catch (_) {}
    return null;
  }

  // --- Profile Fleet Operations ---
  Future<List<Map<String, dynamic>>> getProfiles() async {
    await ensureToken();
    try {
      final res = await http.get(_uri('/api/profiles'), headers: _headers()).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final list = data['profiles'] as List<dynamic>?;
        if (list != null) {
          return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>?> createProfile(String name) async {
    await ensureToken();
    try {
      final res = await http.post(
        _uri('/api/profiles'),
        headers: _headers(),
        body: json.encode({'name': name}),
      ).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        return json.decode(res.body);
      }
    } catch (_) {}
    return null;
  }

  // --- Settings Tab ---
  Future<bool> updateProfileName(String name) async {
    await ensureToken();
    try {
      final res = await http.post(
        _uri('/api/settings'),
        headers: _headers(),
        body: json.encode({'profile_id': profileId, 'profile_name': name}),
      ).timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateLogRetention(String retention) async {
    await ensureToken();
    try {
      final res = await http.post(
        _uri('/api/settings'),
        headers: _headers(),
        body: json.encode({'profile_id': profileId, 'log_retention': retention}),
      ).timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateWeb3Setting(String feature, bool value) async {
    await ensureToken();
    try {
      final res = await http.post(
        _uri('/api/settings'),
        headers: _headers(),
        body: json.encode({
          'profile_id': profileId,
          'web3_feature': feature,
          'web3_value': value,
        }),
      ).timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
