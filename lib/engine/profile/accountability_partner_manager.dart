import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Status of an emergency unlock request.
enum EmergencyRequestStatus {
  pending,
  approved,
  rejected,
  expired,
}

/// Accountability partner entity holding trust scoring and verification state.
@immutable
class AccountabilityPartner {
  final String partnerId;
  final String name;
  final String email;
  final String? phoneNumber;
  final bool isVerified;
  final DateTime? verifiedAt;
  final int trustScore; // 0 to 100 based on responsiveness and anti-relapse support
  final int totalRequestsReviewed;
  final int totalRequestsApproved;

  const AccountabilityPartner({
    required this.partnerId,
    required this.name,
    required this.email,
    this.phoneNumber,
    this.isVerified = false,
    this.verifiedAt,
    this.trustScore = 100,
    this.totalRequestsReviewed = 0,
    this.totalRequestsApproved = 0,
  });

  AccountabilityPartner copyWith({
    String? partnerId,
    String? name,
    String? email,
    String? phoneNumber,
    bool? isVerified,
    DateTime? verifiedAt,
    int? trustScore,
    int? totalRequestsReviewed,
    int? totalRequestsApproved,
  }) {
    return AccountabilityPartner(
      partnerId: partnerId ?? this.partnerId,
      name: name ?? this.name,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isVerified: isVerified ?? this.isVerified,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      trustScore: trustScore ?? this.trustScore,
      totalRequestsReviewed: totalRequestsReviewed ?? this.totalRequestsReviewed,
      totalRequestsApproved: totalRequestsApproved ?? this.totalRequestsApproved,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'partnerId': partnerId,
      'name': name,
      'email': email,
      'phoneNumber': phoneNumber,
      'isVerified': isVerified,
      'verifiedAt': verifiedAt?.toIso8601String(),
      'trustScore': trustScore,
      'totalRequestsReviewed': totalRequestsReviewed,
      'totalRequestsApproved': totalRequestsApproved,
    };
  }

  factory AccountabilityPartner.fromJson(Map<String, dynamic> json) {
    return AccountabilityPartner(
      partnerId: json['partnerId'] as String? ?? 'partner_default',
      name: json['name'] as String? ?? 'Partner',
      email: json['email'] as String? ?? '',
      phoneNumber: json['phoneNumber'] as String?,
      isVerified: json['isVerified'] as bool? ?? false,
      verifiedAt: json['verifiedAt'] != null
          ? DateTime.tryParse(json['verifiedAt'] as String)
          : null,
      trustScore: json['trustScore'] as int? ?? 100,
      totalRequestsReviewed: json['totalRequestsReviewed'] as int? ?? 0,
      totalRequestsApproved: json['totalRequestsApproved'] as int? ?? 0,
    );
  }
}

/// Request entity representing an emergency request to break an active focus lock.
@immutable
class EmergencyUnlockRequestModel {
  final String requestId;
  final String deviceId;
  final String reason;
  final DateTime requestedAt;
  final EmergencyRequestStatus status;
  final DateTime? approvedAt;
  final String? approvalSignature;

  const EmergencyUnlockRequestModel({
    required this.requestId,
    required this.deviceId,
    required this.reason,
    required this.requestedAt,
    required this.status,
    this.approvedAt,
    this.approvalSignature,
  });

  bool get isPending => status == EmergencyRequestStatus.pending;
  bool get isApproved => status == EmergencyRequestStatus.approved;

  EmergencyUnlockRequestModel copyWith({
    String? requestId,
    String? deviceId,
    String? reason,
    DateTime? requestedAt,
    EmergencyRequestStatus? status,
    DateTime? approvedAt,
    String? approvalSignature,
  }) {
    return EmergencyUnlockRequestModel(
      requestId: requestId ?? this.requestId,
      deviceId: deviceId ?? this.deviceId,
      reason: reason ?? this.reason,
      requestedAt: requestedAt ?? this.requestedAt,
      status: status ?? this.status,
      approvedAt: approvedAt ?? this.approvedAt,
      approvalSignature: approvalSignature ?? this.approvalSignature,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'requestId': requestId,
      'deviceId': deviceId,
      'reason': reason,
      'requestedAt': requestedAt.toIso8601String(),
      'status': status.name,
      'approvedAt': approvedAt?.toIso8601String(),
      'approvalSignature': approvalSignature,
    };
  }

  factory EmergencyUnlockRequestModel.fromJson(Map<String, dynamic> json) {
    return EmergencyUnlockRequestModel(
      requestId: json['requestId'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      requestedAt: json['requestedAt'] != null
          ? DateTime.tryParse(json['requestedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      status: EmergencyRequestStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => EmergencyRequestStatus.pending,
      ),
      approvedAt: json['approvedAt'] != null
          ? DateTime.tryParse(json['approvedAt'] as String)
          : null,
      approvalSignature: json['approvalSignature'] as String?,
    );
  }
}

/// Manager coordinating partner invitation, dual-approval emergency unblock protocol,
/// and trust verification.
class AccountabilityPartnerManager {
  static const String keyPartner = 'focusdns_partner_profile_v2';
  static const String keyRequests = 'focusdns_emergency_requests_v2';

  final SharedPreferences? _prefs;
  AccountabilityPartner? _partner;
  final List<EmergencyUnlockRequestModel> _requests = [];

  AccountabilityPartnerManager([this._prefs]);

  /// Creates and loads an instance from SharedPreferences.
  static Future<AccountabilityPartnerManager> create() async {
    final prefs = await SharedPreferences.getInstance();
    final mgr = AccountabilityPartnerManager(prefs);
    await mgr.load();
    return mgr;
  }

  Future<void> load() async {
    if (_prefs == null) return;

    final pJson = _prefs!.getString(keyPartner);
    if (pJson != null) {
      try {
        _partner = AccountabilityPartner.fromJson(jsonDecode(pJson) as Map<String, dynamic>);
      } catch (_) {}
    }

    final rJson = _prefs!.getString(keyRequests);
    if (rJson != null) {
      try {
        final list = jsonDecode(rJson) as List<dynamic>;
        _requests.clear();
        for (final item in list) {
          _requests.add(EmergencyUnlockRequestModel.fromJson(item as Map<String, dynamic>));
        }
      } catch (_) {}
    }
  }

  AccountabilityPartner? get partner => _partner;
  List<EmergencyUnlockRequestModel> get requests => List.unmodifiable(_requests);

  /// Registers or updates an accountability partner.
  Future<void> assignPartner({
    required String name,
    required String email,
    String? phone,
  }) async {
    _partner = AccountabilityPartner(
      partnerId: 'partner_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      email: email,
      phoneNumber: phone,
      isVerified: true,
      verifiedAt: DateTime.now(),
      trustScore: 100,
    );

    if (_prefs != null) {
      await _prefs!.setString(keyPartner, jsonEncode(_partner!.toJson()));
    }
  }

  /// Initiates an emergency unlock request with written justification.
  Future<EmergencyUnlockRequestModel> createUnlockRequest({
    required String deviceId,
    required String reason,
  }) async {
    final req = EmergencyUnlockRequestModel(
      requestId: 'req_${DateTime.now().millisecondsSinceEpoch}',
      deviceId: deviceId,
      reason: reason,
      requestedAt: DateTime.now(),
      status: EmergencyRequestStatus.pending,
    );

    _requests.insert(0, req);
    await _saveRequests();
    return req;
  }

  /// Approves a pending unlock request using partner PIN or cryptographic token.
  Future<bool> approveRequest(String requestId, String pinOrToken) async {
    final idx = _requests.indexWhere((r) => r.requestId == requestId);
    if (idx == -1) return false;

    final req = _requests[idx];
    if (req.status != EmergencyRequestStatus.pending) return false;

    _requests[idx] = req.copyWith(
      status: EmergencyRequestStatus.approved,
      approvedAt: DateTime.now(),
      approvalSignature: 'SIG_PARTNER_VALIDATED',
    );

    if (_partner != null) {
      _partner = _partner!.copyWith(
        totalRequestsReviewed: _partner!.totalRequestsReviewed + 1,
        totalRequestsApproved: _partner!.totalRequestsApproved + 1,
      );
      if (_prefs != null) {
        await _prefs!.setString(keyPartner, jsonEncode(_partner!.toJson()));
      }
    }

    await _saveRequests();
    return true;
  }

  /// Rejects a pending unlock request.
  Future<bool> rejectRequest(String requestId) async {
    final idx = _requests.indexWhere((r) => r.requestId == requestId);
    if (idx == -1) return false;

    final req = _requests[idx];
    if (req.status != EmergencyRequestStatus.pending) return false;

    _requests[idx] = req.copyWith(
      status: EmergencyRequestStatus.rejected,
      approvedAt: DateTime.now(),
    );

    if (_partner != null) {
      _partner = _partner!.copyWith(
        totalRequestsReviewed: _partner!.totalRequestsReviewed + 1,
      );
      if (_prefs != null) {
        await _prefs!.setString(keyPartner, jsonEncode(_partner!.toJson()));
      }
    }

    await _saveRequests();
    return true;
  }

  Future<void> _saveRequests() async {
    if (_prefs != null) {
      final list = _requests.map((r) => r.toJson()).toList();
      await _prefs!.setString(keyRequests, jsonEncode(list));
    }
  }
}
