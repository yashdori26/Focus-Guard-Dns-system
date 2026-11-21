import 'package:flutter/material.dart';
import '../../../engine/surgical/catalog/surgical_subfeature_types.dart';
import '../../../engine/surgical/core/surgical_policy_evaluator.dart';
import '../../../engine/surgical/models/surgical_rule_model.dart';
import '../../../engine/surgical/models/view_node_target.dart';

/// Studio screen for crafting user-defined surgical decoupling rules for custom apps.
class CustomSurgicalRuleBuilderScreen extends StatefulWidget {
  final SurgicalPolicyEvaluator evaluator;

  const CustomSurgicalRuleBuilderScreen({
    super.key,
    required this.evaluator,
  });

  @override
  State<CustomSurgicalRuleBuilderScreen> createState() =>
      _CustomSurgicalRuleBuilderScreenState();
}

class _CustomSurgicalRuleBuilderScreenState
    extends State<CustomSurgicalRuleBuilderScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _packageController = TextEditingController();
  final TextEditingController _glyphController = TextEditingController(text: '🌐');
  final TextEditingController _domainsController = TextEditingController();
  final TextEditingController _pathsController = TextEditingController();
  final TextEditingController _chatDomainsController = TextEditingController();
  final TextEditingController _viewResourceIdsController = TextEditingController();
  final TextEditingController _testInputController = TextEditingController();

  SurgicalSubfeature _selectedSubfeature = SurgicalSubfeature.reelsOrShorts;
  ViewInterceptionAction _selectedAction = ViewInterceptionAction.navigateBack;
  String? _testResultText;
  Color _testResultColor = Colors.grey;

  @override
  void dispose() {
    _nameController.dispose();
    _packageController.dispose();
    _glyphController.dispose();
    _domainsController.dispose();
    _pathsController.dispose();
    _chatDomainsController.dispose();
    _viewResourceIdsController.dispose();
    _testInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF13151B) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E222B) : Colors.white;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: const Text('New Custom Surgical Rule'),
        actions: [
          TextButton(
            onPressed: _saveCustomRule,
            child: const Text('Save Rule', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Basic Info Card
              _buildSectionCard(
                title: 'PLATFORM IDENTITY',
                isDark: isDark,
                cardColor: cardColor,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 60,
                        child: TextFormField(
                          controller: _glyphController,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(labelText: 'Icon'),
                          validator: (v) => (v == null || v.isEmpty) ? '!' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Platform Name',
                            hintText: 'e.g. Bluesky or Mastodon',
                          ),
                          validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _packageController,
                    decoration: const InputDecoration(
                      labelText: 'Android Package Name',
                      hintText: 'e.g. xyz.blueskyweb.app',
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Subfeature & Action Card
              _buildSectionCard(
                title: 'SUB-FEATURE CLASSIFICATION',
                isDark: isDark,
                cardColor: cardColor,
                children: [
                  DropdownButtonFormField<SurgicalSubfeature>(
                    value: _selectedSubfeature,
                    decoration: const InputDecoration(labelText: 'Sub-Feature Category to Sever'),
                    items: SurgicalSubfeature.values.map((f) {
                      final meta = SurgicalSubfeatureRegistry.getMetadata(f);
                      return DropdownMenuItem(
                        value: f,
                        child: Text('${meta.displayName} (Dopamine: ${meta.dopamineAddictionScore})'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedSubfeature = val;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ViewInterceptionAction>(
                    value: _selectedAction,
                    decoration: const InputDecoration(labelText: 'Interception Action'),
                    items: ViewInterceptionAction.values.map((a) {
                      return DropdownMenuItem(
                        value: a,
                        child: Text(a.name),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedAction = val;
                        });
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Network Endpoints Card
              _buildSectionCard(
                title: 'NETWORK SINKHOLE & WHITELISTS',
                isDark: isDark,
                cardColor: cardColor,
                children: [
                  TextFormField(
                    controller: _domainsController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Severed Video & Feed Domains (comma-separated)',
                      hintText: 'video.app.com, *.cdn.app.com',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _pathsController,
                    decoration: const InputDecoration(
                      labelText: 'Severed URL Path Prefixes (comma-separated)',
                      hintText: '/reels, /shorts, /explore',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _chatDomainsController,
                    decoration: const InputDecoration(
                      labelText: 'Protected Chat & DM Domains (comma-separated)',
                      hintText: 'chat.app.com, edge-chat.app.com',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // View Node Target Card
              _buildSectionCard(
                title: 'NATIVE VIEW HIERARCHY PATTERNS',
                isDark: isDark,
                cardColor: cardColor,
                children: [
                  TextFormField(
                    controller: _viewResourceIdsController,
                    decoration: const InputDecoration(
                      labelText: 'Accessibility Resource IDs (comma-separated)',
                      hintText: 'reel_viewer, tab_reels, explore_container',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Interactive Rule Sandbox / Tester
              _buildSectionCard(
                title: 'INTERACTIVE RULE SANDBOX TESTER',
                isDark: isDark,
                cardColor: cardColor,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _testInputController,
                          decoration: const InputDecoration(
                            hintText: 'Enter test domain or URL...',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _runSandboxTest,
                        child: const Text('Test'),
                      ),
                    ],
                  ),
                  if (_testResultText != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _testResultColor.withAlpha(isDark ? 30 : 20),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _testResultColor.withAlpha(100)),
                      ),
                      child: Text(
                        _testResultText!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _testResultColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required bool isDark,
    required Color cardColor,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF2C3240) : const Color(0xFFE2E7F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  void _runSandboxTest() {
    final input = _testInputController.text.trim();
    if (input.isEmpty) return;

    final severedDomains = _parseList(_domainsController.text);
    final chatDomains = _parseList(_chatDomainsController.text);

    if (chatDomains.any((d) => input.contains(d))) {
      setState(() {
        _testResultText = 'WHITELISTED: Communication Gateway ($input allowed through)';
        _testResultColor = const Color(0xFF10B981);
      });
      return;
    }

    if (severedDomains.any((d) => input.contains(d.replaceAll('*.', '')))) {
      setState(() {
        _testResultText = 'BLACKHOLED: Severed ${_selectedSubfeature.name} ($input sinkholed)';
        _testResultColor = const Color(0xFFEF4444);
      });
      return;
    }

    setState(() {
      _testResultText = 'PASS-THROUGH: No pattern matched for $input';
      _testResultColor = Colors.grey;
    });
  }

  void _saveCustomRule() {
    if (!_formKey.currentState!.validate()) return;

    final platformId = _nameController.text.trim().toLowerCase().replaceAll(' ', '_');
    final severedDomains = _parseList(_domainsController.text);
    final paths = _parseList(_pathsController.text);
    final chatDomains = _parseList(_chatDomainsController.text);
    final viewIds = _parseList(_viewResourceIdsController.text);

    final viewTargets = viewIds.isNotEmpty
        ? [
            ViewNodeTarget(
              targetId: '${platformId}_custom_target',
              packageName: _packageController.text.trim(),
              resourceIdPatterns: viewIds,
              defaultAction: _selectedAction,
              description: 'Custom view sentinel for ${_nameController.text.trim()}',
            ),
          ]
        : <ViewNodeTarget>[];

    final newRule = SurgicalRuleModel(
      platformId: platformId,
      displayName: _nameController.text.trim(),
      iconGlyph: _glyphController.text.trim(),
      packageNames: [_packageController.text.trim()],
      subfeatureToggles: {
        _selectedSubfeature: true,
        SurgicalSubfeature.directMessages: false,
      },
      subfeatureDomains: {
        _selectedSubfeature: severedDomains,
      },
      subfeatureUrlPaths: {
        _selectedSubfeature: paths,
      },
      chatWhitelistDomains: chatDomains,
      searchWhitelistDomains: const [],
      viewNodeTargets: viewTargets,
    );

    // Insert into evaluator
    for (final d in severedDomains) {
      widget.evaluator.trieMatcher.insertDomain(
        domain: d,
        platformId: platformId,
        subfeature: _selectedSubfeature,
        action: _selectedAction,
      );
    }

    for (final c in chatDomains) {
      widget.evaluator.trieMatcher.insertDomain(
        domain: c,
        platformId: platformId,
        subfeature: SurgicalSubfeature.directMessages,
        isCommunicationWhitelist: true,
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Custom surgical rule saved for ${newRule.displayName}'),
        backgroundColor: const Color(0xFF10B981),
      ),
    );
    Navigator.of(context).pop();
  }

  List<String> _parseList(String raw) {
    if (raw.trim().isEmpty) return [];
    return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }
}
