import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Dart client adapter for FocusDNS Go Cloud API (`/api/v1/...`).
/// Handles Argon2id auth, TOTP 2FA, session sync, privacy rollups, and rule packs.
class CloudApiAdapter {
  final String baseUrl;
  final http.Client _client;
  String? _authToken;

  CloudApiAdapter({
    this.baseUrl = 'http://localhost:8080',
    http.Client? client,
  }) : _client = client ?? http.Client();

  void setAuthToken(String token) {
    _authToken = token;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_authToken != null) 'Authorization': 'Bearer $_authToken',
      };

  /// Registers user account with Argon2id password hash generation.
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/auth/register'),
      headers: _headers,
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Registration failed: ${response.body}');
  }

  /// Logs into account using Argon2id verification and optional TOTP 2FA code.
  Future<String> login({
    required String email,
    required String password,
    String? totpCode,
    String? deviceId,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/auth/login'),
      headers: _headers,
      body: jsonEncode({
        'email': email,
        'password': password,
        'totp_code': totpCode ?? '',
        'device_id': deviceId ?? 'dev_client',
      }),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final token = data['access_token'] as String;
      _authToken = token;
      return token;
    }
    throw Exception('Login failed: ${response.body}');
  }

  /// Syncs an active focus session snapshot with precomputed absolute timeline.
  Future<bool> syncSession(Map<String, dynamic> sessionSnapshot) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/sessions/sync'),
      headers: _headers,
      body: jsonEncode(sessionSnapshot),
    );
    return response.statusCode == 200;
  }

  /// Ingests privacy-first hourly category count buckets (Option A - Zero Domain Logs).
  Future<bool> ingestHourlyRollup({
    required String deviceId,
    required int hourBucketEpochMs,
    required Map<String, Map<String, int>> categoryCounts,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/v1/analytics/rollup'),
      headers: _headers,
      body: jsonEncode({
        'device_id': deviceId,
        'hour_bucket_epoch_ms': hourBucketEpochMs,
        'category_counts': categoryCounts,
      }),
    );
    return response.statusCode == 200;
  }

  /// Fetches privacy-aggregated analytics summary (24h, 7d, 30d, 2y).
  Future<Map<String, dynamic>> fetchAnalyticsSummary({String range = '24h'}) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/analytics/summary?range=$range'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to fetch analytics summary: ${response.body}');
  }

  /// Downloads latest signed Ed25519 delta rule pack from Cloud CDN.
  Future<Map<String, dynamic>> fetchLatestRulePack() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/v1/rules/latest'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to fetch rule pack: ${response.body}');
  }
}
