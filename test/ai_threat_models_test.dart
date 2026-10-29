import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/models/ai_threat_models.dart';

void main() {
  group('AI Threat Models Unit Tests', () {
    test('HomographCharacter serialization and deserialization', () {
      final json = {
        'character': 'а',
        'codepoint': 'U+0430',
        'confusable_with': 'a',
        'script': 'CYRILLIC',
      };

      final c = HomographCharacter.fromJson(json);
      expect(c.character, 'а');
      expect(c.codepoint, 'U+0430');
      expect(c.confusableWith, 'a');
      expect(c.script, 'CYRILLIC');

      final out = c.toJson();
      expect(out['character'], 'а');
      expect(out['codepoint'], 'U+0430');
      expect(out['confusable_with'], 'a');
      expect(out['script'], 'CYRILLIC');
    });

    test('HomographAnalysis serialization and fallback defaults', () {
      final json = {
        'original_domain': 'xn--pple-43d.com',
        'unicode_domain': 'аpple.com',
        'skeleton': 'apple.com',
        'is_threat': true,
        'attack_type': 'MIXED_SCRIPT_CONFUSABLE',
        'spoofed_brand': 'Apple',
        'risk_score': 92.5,
        'explanation': 'Mixed Latin-Cyrillic script homograph targeting Apple.',
        'confusable_details': [
          {
            'character': 'а',
            'codepoint': 'U+0430',
            'confusable_with': 'a',
            'script': 'CYRILLIC',
          }
        ],
      };

      final h = HomographAnalysis.fromJson(json);
      expect(h.originalDomain, 'xn--pple-43d.com');
      expect(h.unicodeDomain, 'аpple.com');
      expect(h.skeleton, 'apple.com');
      expect(h.isThreat, isTrue);
      expect(h.attackType, 'MIXED_SCRIPT_CONFUSABLE');
      expect(h.spoofedBrand, 'Apple');
      expect(h.riskScore, 92.5);
      expect(h.explanation, contains('targeting Apple'));
      expect(h.confusables.length, 1);
      expect(h.confusables.first.confusableWith, 'a');

      final out = h.toJson();
      expect(out['original_domain'], 'xn--pple-43d.com');
      expect(out['spoofed_brand'], 'Apple');
      expect(out['is_threat'], isTrue);
    });

    test('DgaAnalysis serialization and probability calculations', () {
      final json = {
        'domain': 'bcdfghjklmnpqrstvwxyz.org',
        'is_dga': true,
        'probability': 0.942,
        'confidence_score': 94.2,
        'predicted_family': 'Conficker',
        'entropy': 3.85,
        'vowel_ratio': 0.05,
        'explanation': 'High Shannon entropy (3.85) and zero vowel syllable structure.',
      };

      final d = DgaAnalysis.fromJson(json);
      expect(d.domain, 'bcdfghjklmnpqrstvwxyz.org');
      expect(d.isDga, isTrue);
      expect(d.probability, 0.942);
      expect(d.confidenceScore, 94.2);
      expect(d.predictedFamily, 'Conficker');
      expect(d.entropy, 3.85);
      expect(d.vowelRatio, 0.05);
      expect(d.explanation, contains('High Shannon entropy'));

      final out = d.toJson();
      expect(out['domain'], 'bcdfghjklmnpqrstvwxyz.org');
      expect(out['is_dga'], isTrue);
      expect(out['predicted_family'], 'Conficker');
    });

    test('CategoryDistribution serialization and distraction detection', () {
      final json = {
        'domain': 'playstation.com',
        'primary_category': 'GAMING',
        'confidence': 0.88,
        'is_distracting': true,
        'category_probabilities': {
          'GAMING': 0.88,
          'STREAMING': 0.08,
          'PRODUCTIVITY': 0.04,
        },
        'explanation': 'Classified as GAMING with 88.0% confidence.',
      };

      final cat = CategoryDistribution.fromJson(json);
      expect(cat.domain, 'playstation.com');
      expect(cat.primaryCategory, 'GAMING');
      expect(cat.confidence, 0.88);
      expect(cat.isDistracting, isTrue);
      expect(cat.probabilities['GAMING'], 0.88);
      expect(cat.explanation, contains('Classified as GAMING'));

      final out = cat.toJson();
      expect(out['domain'], 'playstation.com');
      expect(out['primary_category'], 'GAMING');
      expect(out['is_distracting'], isTrue);
    });

    test('AiTelemetrySnapshot serialization and parsing', () {
      final json = {
        'total_queries_analyzed': 45200,
        'total_threats_blocked': 1340,
        'homographs_blocked': 620,
        'dga_blocked': 510,
        'phishing_blocked': 210,
        'exemptions_passed': 48,
        'avg_inference_latency_us': 24.5,
        'is_active_focus_locked': true,
      };

      final telem = AiTelemetrySnapshot.fromJson(json);
      expect(telem.totalQueries, 45200);
      expect(telem.totalThreatsBlocked, 1340);
      expect(telem.homographsBlocked, 620);
      expect(telem.dgaBlocked, 510);
      expect(telem.phishingBlocked, 210);
      expect(telem.exemptionsPassed, 48);
      expect(telem.avgLatencyUs, 24.5);
      expect(telem.isLocked, isTrue);

      final out = telem.toJson();
      expect(out['total_queries_analyzed'], 45200);
      expect(out['is_active_focus_locked'], isTrue);
    });

    test('EdgeThreatEvent serialization and parsing', () {
      final json = {
        'timestamp': 1730000000,
        'client_ip': '192.168.1.140',
        'client_mac': 'AA:BB:CC:11:22:33',
        'device_name': 'Living Room LG Smart TV',
        'domain': 'bcdfghjklmnpqrstvwxyz.org',
        'threat_type': 'DGA_MALWARE',
        'risk_score': 95.0,
        'action': 'BLOCKED_SINKHOLE',
        'reason': 'DGA C2 domain blocked by router gateway interceptor.',
      };

      final ev = EdgeThreatEvent.fromJson(json);
      expect(ev.timestamp, 1730000000);
      expect(ev.clientIp, '192.168.1.140');
      expect(ev.clientMac, 'AA:BB:CC:11:22:33');
      expect(ev.deviceName, 'Living Room LG Smart TV');
      expect(ev.domain, 'bcdfghjklmnpqrstvwxyz.org');
      expect(ev.threatType, 'DGA_MALWARE');
      expect(ev.riskScore, 95.0);
      expect(ev.action, 'BLOCKED_SINKHOLE');
      expect(ev.reason, contains('DGA C2 domain'));

      final out = ev.toJson();
      expect(out['device_name'], 'Living Room LG Smart TV');
      expect(out['action'], 'BLOCKED_SINKHOLE');
    });

    test('AiThreatVerdict composite evaluation model', () {
      final json = {
        'domain': 'аpple.com',
        'is_threat': true,
        'action': 'BLOCK',
        'risk_score': 95.5,
        'reason': 'Impersonation of Apple detected via Cyrillic homoglyph.',
        'threat_type': 'HOMOGRAPH_TYPOSQUAT',
        'detected_brand': 'Apple',
        'dga_family': null,
        'category': 'PHISHING',
        'latency_us': 18.2,
        'cached': false,
      };

      final verdict = AiThreatVerdict.fromJson(json);
      expect(verdict.domain, 'аpple.com');
      expect(verdict.isThreat, isTrue);
      expect(verdict.action, 'BLOCK');
      expect(verdict.riskScore, 95.5);
      expect(verdict.threatType, 'HOMOGRAPH_TYPOSQUAT');
      expect(verdict.detectedBrand, 'Apple');
      expect(verdict.dgaFamily, isNull);
      expect(verdict.category, 'PHISHING');
      expect(verdict.latencyUs, 18.2);
      expect(verdict.cached, isFalse);

      final out = verdict.toJson();
      expect(out['domain'], 'аpple.com');
      expect(out['action'], 'BLOCK');
      expect(out['threat_type'], 'HOMOGRAPH_TYPOSQUAT');
    });

    test('AiThreatVerdict Life Safety Exemption pass logic', () {
      final json = {
        'domain': 'push.apple.com',
        'is_threat': false,
        'action': 'ALLOW',
        'risk_score': 0.0,
        'reason': 'Apple APNs push notification infrastructure exempt from AI blocking.',
        'threat_type': 'LIFE_SAFETY_EXEMPTION',
        'detected_brand': 'Apple',
        'category': 'SYSTEM_EXEMPT',
        'latency_us': 0.5,
        'cached': true,
      };

      final verdict = AiThreatVerdict.fromJson(json);
      expect(verdict.domain, 'push.apple.com');
      expect(verdict.isThreat, isFalse);
      expect(verdict.action, 'ALLOW');
      expect(verdict.riskScore, 0.0);
      expect(verdict.threatType, 'LIFE_SAFETY_EXEMPTION');
      expect(verdict.cached, isTrue);
    });
  });
}
