/// FocusDNS Flutter Screen - Unicode TR39 Homograph & Typosquat Inspector
/// Visual debugger for IDN homograph lookalikes, script composition analysis,
/// and brand impersonation detection.

import 'package:flutter/material.dart';
import '../models/ai_threat_models.dart';
import '../services/ai_threat_service.dart';
import '../widgets/ai_risk_meter.dart';

class HomographInspectorScreen extends StatefulWidget {
  final AiThreatService? threatService;

  const HomographInspectorScreen({Key? key, this.threatService}) : super(key: key);

  @override
  State<HomographInspectorScreen> createState() => _HomographInspectorScreenState();
}

class _HomographInspectorScreenState extends State<HomographInspectorScreen> {
  late AiThreatService _service;
  final TextEditingController _controller = TextEditingController(text: '\u0430pple.com');

  bool _isLoading = false;
  HomographAnalysis? _analysis;

  final List<String> _sampleDomains = [
    '\u0430pple.com', // Cyrillic 'а'
    'g\u043e\u043egle.com', // Cyrillic 'о'
    'paypa1.com', // Levenshtein typo
    'microsoft.com', // Benign
  ];

  @override
  void initState() {
    super.initState();
    _service = widget.threatService ?? AiThreatService();
    _inspectDomain(_controller.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _inspectDomain(String domain) async {
    final clean = domain.trim();
    if (clean.isEmpty) return;

    if (mounted) {
      setState(() => _isLoading = true);
    }
    final result = await _service.checkHomograph(clean);
    if (mounted) {
      setState(() {
        _analysis = result;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        title: const Text('TR39 Homograph Inspector'),
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Header Card
          _buildHeaderCard(),
          const SizedBox(height: 16),

          // Search and Quick Samples
          _buildSearchAndSamples(),
          const SizedBox(height: 20),

          // Analysis Output
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(color: Color(0xFF10B981)),
              ),
            )
          else if (_analysis != null)
            _buildAnalysisResult(_analysis!),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.translate, color: Color(0xFF10B981), size: 20),
              SizedBox(width: 8),
              Text(
                'Unicode TR39 Confusable Standard',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Unmasks malicious lookalike characters (Cyrillic, Greek, Armenian) replacing Latin characters to spoof banking, tech, and crypto portals.',
            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndSamples() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Enter domain or paste Punycode (xn--...)',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (val) => _inspectDomain(val),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: () => _inspectDomain(_controller.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Analyze'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: _sampleDomains.map((d) {
            return ActionChip(
              label: Text(d, style: const TextStyle(fontSize: 11, color: Colors.white70)),
              backgroundColor: const Color(0xFF1E293B),
              onPressed: () {
                _controller.text = d;
                _inspectDomain(d);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildAnalysisResult(HomographAnalysis res) {
    final isThreat = res.isThreat;
    final color = isThreat ? const Color(0xFFEF4444) : const Color(0xFF10B981);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isThreat ? 'SPOOFING THREAT DETECTED' : 'CLEAN DOMAIN',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 1.0,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  res.attackType,
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AiRiskMeter(score: res.riskScore),
          const SizedBox(height: 16),

          // Skeleton and Unicode Display
          _buildInfoRow('Input Domain:', res.originalDomain),
          _buildInfoRow('Unicode Normalized:', res.unicodeDomain),
          _buildInfoRow('Visual Skeleton:', res.skeleton),
          if (res.spoofedBrand != null)
            _buildInfoRow('Targeted Brand:', res.spoofedBrand!.toUpperCase(), isAlert: true),

          const SizedBox(height: 12),
          Text(
            res.explanation,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),

          if (res.confusables.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Confusable Character Breakdown:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.separated(
                itemCount: res.confusables.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                separatorBuilder: (_, __) => Divider(color: Colors.white.withOpacity(0.06), height: 1),
                itemBuilder: (context, idx) {
                  final c = res.confusables[idx];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              c.character,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFEF4444),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '(${c.codepoint}) in ${c.script}',
                              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            const Text('mimics Latin ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            Text(
                              c.confusableWith,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isAlert = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[400])),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isAlert ? const Color(0xFFEF4444) : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
