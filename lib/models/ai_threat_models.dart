/// FocusDNS Flutter Client - On-Device AI Threat Hunting Models
/// Represents structured verdicts, homograph lookalikes, DGA probabilities,
/// dynamic categories, and edge router threat events.

class AiThreatVerdict {
  final String domain;
  final bool isThreat;
  final String action;
  final double riskScore;
  final String reason;
  final String threatType;
  final String? detectedBrand;
  final String? dgaFamily;
  final String category;
  final double latencyUs;
  final bool cached;

  AiThreatVerdict({
    required this.domain,
    required this.isThreat,
    required this.action,
    required this.riskScore,
    required this.reason,
    required this.threatType,
    this.detectedBrand,
    this.dgaFamily,
    required this.category,
    required this.latencyUs,
    this.cached = false,
  });

  factory AiThreatVerdict.fromJson(Map<String, dynamic> json) {
    return AiThreatVerdict(
      domain: json['domain'] as String? ?? '',
      isThreat: json['is_threat'] as bool? ?? false,
      action: json['action'] as String? ?? 'ALLOW',
      riskScore: (json['risk_score'] as num?)?.toDouble() ??
          (json['composite_risk_score'] as num?)?.toDouble() ??
          0.0,
      reason: json['reason'] as String? ?? json['primary_reason'] as String? ?? 'Clean',
      threatType: json['threat_type'] as String? ?? 'NONE',
      detectedBrand: json['detected_brand'] as String?,
      dgaFamily: json['dga_family'] as String?,
      category: json['category'] as String? ?? json['primary_category'] as String? ?? 'Unclassified',
      latencyUs: (json['latency_us'] as num?)?.toDouble() ??
          (json['inference_latency_us'] as num?)?.toDouble() ??
          0.0,
      cached: json['cached'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'domain': domain,
      'is_threat': isThreat,
      'action': action,
      'risk_score': riskScore,
      'reason': reason,
      'threat_type': threatType,
      'detected_brand': detectedBrand,
      'dga_family': dgaFamily,
      'category': category,
      'latency_us': latencyUs,
      'cached': cached,
    };
  }
}

class HomographCharacter {
  final String character;
  final String codepoint;
  final String confusableWith;
  final String script;

  HomographCharacter({
    required this.character,
    required this.codepoint,
    required this.confusableWith,
    required this.script,
  });

  factory HomographCharacter.fromJson(Map<String, dynamic> json) {
    return HomographCharacter(
      character: json['character'] as String? ?? '',
      codepoint: json['codepoint'] as String? ?? '',
      confusableWith: json['confusable_with'] as String? ?? '',
      script: json['script'] as String? ?? 'Unknown',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'character': character,
      'codepoint': codepoint,
      'confusable_with': confusableWith,
      'script': script,
    };
  }
}

class HomographAnalysis {
  final String originalDomain;
  final String unicodeDomain;
  final String skeleton;
  final bool isThreat;
  final String attackType;
  final String? spoofedBrand;
  final double riskScore;
  final String explanation;
  final List<HomographCharacter> confusables;

  HomographAnalysis({
    required this.originalDomain,
    required this.unicodeDomain,
    required this.skeleton,
    required this.isThreat,
    required this.attackType,
    this.spoofedBrand,
    required this.riskScore,
    required this.explanation,
    required this.confusables,
  });

  factory HomographAnalysis.fromJson(Map<String, dynamic> json) {
    final list = json['confusable_details'] as List? ?? json['confusables'] as List? ?? [];
    return HomographAnalysis(
      originalDomain: json['original_domain'] as String? ?? '',
      unicodeDomain: json['unicode_domain'] as String? ?? '',
      skeleton: json['skeleton'] as String? ?? '',
      isThreat: json['is_threat'] as bool? ?? false,
      attackType: json['attack_type'] as String? ?? 'NONE',
      spoofedBrand: json['spoofed_brand'] as String?,
      riskScore: (json['risk_score'] as num?)?.toDouble() ?? 0.0,
      explanation: json['explanation'] as String? ?? '',
      confusables: list.map((e) => HomographCharacter.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'original_domain': originalDomain,
      'unicode_domain': unicodeDomain,
      'skeleton': skeleton,
      'is_threat': isThreat,
      'attack_type': attackType,
      'spoofed_brand': spoofedBrand,
      'risk_score': riskScore,
      'explanation': explanation,
      'confusables': confusables.map((e) => e.toJson()).toList(),
    };
  }
}

class DgaAnalysis {
  final String domain;
  final bool isDga;
  final double probability;
  final double confidenceScore;
  final String? predictedFamily;
  final double entropy;
  final double vowelRatio;
  final String explanation;

  DgaAnalysis({
    required this.domain,
    required this.isDga,
    required this.probability,
    required this.confidenceScore,
    this.predictedFamily,
    required this.entropy,
    required this.vowelRatio,
    required this.explanation,
  });

  factory DgaAnalysis.fromJson(Map<String, dynamic> json) {
    return DgaAnalysis(
      domain: json['domain'] as String? ?? '',
      isDga: json['is_dga'] as bool? ?? false,
      probability: (json['probability'] as num?)?.toDouble() ?? 0.0,
      confidenceScore: (json['confidence_score'] as num?)?.toDouble() ?? 0.0,
      predictedFamily: json['predicted_family'] as String? ?? json['attributed_family'] as String?,
      entropy: (json['entropy'] as num?)?.toDouble() ?? 0.0,
      vowelRatio: (json['vowel_ratio'] as num?)?.toDouble() ?? 0.0,
      explanation: json['explanation'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'domain': domain,
      'is_dga': isDga,
      'probability': probability,
      'confidence_score': confidenceScore,
      'predicted_family': predictedFamily,
      'entropy': entropy,
      'vowel_ratio': vowelRatio,
      'explanation': explanation,
    };
  }
}

class CategoryDistribution {
  final String domain;
  final String primaryCategory;
  final double confidence;
  final bool isDistracting;
  final Map<String, double> probabilities;
  final String explanation;

  CategoryDistribution({
    required this.domain,
    required this.primaryCategory,
    required this.confidence,
    required this.isDistracting,
    required this.probabilities,
    required this.explanation,
  });

  factory CategoryDistribution.fromJson(Map<String, dynamic> json) {
    final rawProbs = json['category_probabilities'] as Map<String, dynamic>? ?? {};
    final probs = <String, double>{};
    rawProbs.forEach((k, v) {
      probs[k] = (v as num).toDouble();
    });

    return CategoryDistribution(
      domain: json['domain'] as String? ?? '',
      primaryCategory: json['primary_category'] as String? ?? 'Unclassified',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      isDistracting: json['is_distracting'] as bool? ?? false,
      probabilities: probs,
      explanation: json['explanation'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'domain': domain,
      'primary_category': primaryCategory,
      'confidence': confidence,
      'is_distracting': isDistracting,
      'category_probabilities': probabilities,
      'explanation': explanation,
    };
  }
}

class AiTelemetrySnapshot {
  final int totalQueries;
  final int totalThreatsBlocked;
  final int homographsBlocked;
  final int dgaBlocked;
  final int phishingBlocked;
  final int exemptionsPassed;
  final double avgLatencyUs;
  final bool isLocked;

  AiTelemetrySnapshot({
    required this.totalQueries,
    required this.totalThreatsBlocked,
    required this.homographsBlocked,
    required this.dgaBlocked,
    required this.phishingBlocked,
    required this.exemptionsPassed,
    required this.avgLatencyUs,
    required this.isLocked,
  });

  factory AiTelemetrySnapshot.fromJson(Map<String, dynamic> json) {
    return AiTelemetrySnapshot(
      totalQueries: json['total_queries_analyzed'] as int? ??
          json['total_domains_analyzed'] as int? ??
          0,
      totalThreatsBlocked: json['total_threats_blocked'] as int? ?? 0,
      homographsBlocked: json['homographs_blocked'] as int? ?? 0,
      dgaBlocked: json['dga_blocked'] as int? ?? json['dgas_blocked'] as int? ?? 0,
      phishingBlocked: json['phishing_blocked'] as int? ?? 0,
      exemptionsPassed: json['exemptions_passed'] as int? ?? json['exempt_bypasses'] as int? ?? 0,
      avgLatencyUs: (json['avg_inference_latency_us'] as num?)?.toDouble() ?? 0.0,
      isLocked: json['is_active_focus_locked'] as bool? ?? json['is_locked'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_queries_analyzed': totalQueries,
      'total_threats_blocked': totalThreatsBlocked,
      'homographs_blocked': homographsBlocked,
      'dga_blocked': dgaBlocked,
      'phishing_blocked': phishingBlocked,
      'exemptions_passed': exemptionsPassed,
      'avg_inference_latency_us': avgLatencyUs,
      'is_active_focus_locked': isLocked,
    };
  }
}

class EdgeThreatEvent {
  final int timestamp;
  final String clientIp;
  final String clientMac;
  final String deviceName;
  final String domain;
  final String threatType;
  final double riskScore;
  final String action;
  final String reason;

  EdgeThreatEvent({
    required this.timestamp,
    required this.clientIp,
    required this.clientMac,
    required this.deviceName,
    required this.domain,
    required this.threatType,
    required this.riskScore,
    required this.action,
    required this.reason,
  });

  factory EdgeThreatEvent.fromJson(Map<String, dynamic> json) {
    return EdgeThreatEvent(
      timestamp: json['timestamp'] as int? ?? 0,
      clientIp: json['client_ip'] as String? ?? '',
      clientMac: json['client_mac'] as String? ?? '',
      deviceName: json['device_name'] as String? ?? 'Unknown Device',
      domain: json['domain'] as String? ?? '',
      threatType: json['threat_type'] as String? ?? 'NONE',
      riskScore: (json['risk_score'] as num?)?.toDouble() ?? 0.0,
      action: json['action'] as String? ?? 'ALLOW',
      reason: json['reason'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp,
      'client_ip': clientIp,
      'client_mac': clientMac,
      'device_name': deviceName,
      'domain': domain,
      'threat_type': threatType,
      'risk_score': riskScore,
      'action': action,
      'reason': reason,
    };
  }
}
