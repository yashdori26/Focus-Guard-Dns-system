// FocusDNS Enterprise Classroom & Fleet Orchestrator Screen

import 'dart:async';
import 'package:flutter/material.dart';
import '../models/enterprise_models.dart';
import '../services/enterprise_service.dart';

class EnterpriseClassroomScreen extends StatefulWidget {
  final String orgId;
  final EnterpriseService? service;

  const EnterpriseClassroomScreen({
    super.key,
    this.orgId = 'org_springfield',
    this.service,
  });

  @override
  State<EnterpriseClassroomScreen> createState() => _EnterpriseClassroomScreenState();
}

class _EnterpriseClassroomScreenState extends State<EnterpriseClassroomScreen> {
  late final EnterpriseService _service;
  bool _isLoading = true;
  List<ClassroomSessionModel> _sessions = [];
  ClassroomSessionModel? _selectedSession;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? EnterpriseService();
    _loadSessions();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _selectedSession != null && _selectedSession!.remainingSeconds > 0) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
    try {
      final sessions = await _service.fetchClassroomSessions(orgId: widget.orgId);
      if (mounted) {
        setState(() {
          _sessions = sessions;
          if (_sessions.isNotEmpty) {
            _selectedSession = _sessions.first;
          }
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatSeconds(int totalSeconds) {
    if (totalSeconds <= 0) return '00:00';
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _changeFocusMode(ClassroomFocusMode mode) async {
    if (_selectedSession == null) return;
    final success = await _service.setClassroomFocusMode(_selectedSession!.sessionId, mode);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Classroom mode switched to ${mode.displayName}'),
          backgroundColor: Colors.teal[800],
        ),
      );
      _loadSessions();
    }
  }

  Future<void> _toggleStrictExamLock() async {
    if (_selectedSession == null) return;

    final targetMode = _selectedSession!.mode == ClassroomFocusMode.strictExamMode
        ? ClassroomFocusMode.normalProtection
        : ClassroomFocusMode.strictExamMode;

    if (targetMode == ClassroomFocusMode.strictExamMode) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock, color: Colors.amber),
              SizedBox(width: 8),
              Text('Strict Exam Lockdown'),
            ],
          ),
          content: const Text(
            'This will freeze all student devices to exam-only domains in sub-50ms.\n\n'
            'Inviolable Law: Domain whitelisting is strictly prohibited during active exam mode.\n\n'
            'Life-safety emergency domains (911.gov, update services) remain unconditionally exempt.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[900]),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Engage Lockdown', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    await _changeFocusMode(targetMode);
  }

  Future<void> _showAddAllowedDomainDialog() async {
    if (_selectedSession == null) return;

    if (_selectedSession!.mode == ClassroomFocusMode.strictExamMode) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.block, color: Colors.red),
              SizedBox(width: 8),
              Text('Access Denied (Code 5)'),
            ],
          ),
          content: const Text(
            'ERROR_ACCESS_DENIED (5):\n\n'
            'Conditional Whitelisting Law strictly prohibits modifying permitted domains '
            'while Strict Exam Lockdown is active.\n\n'
            'Please end or switch focus mode before modifying rules.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Understood'),
            ),
          ],
        ),
      );
      return;
    }

    final controller = TextEditingController();
    final added = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Permitted Exam Domain'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Domain (e.g. exam.collegeboard.org)',
            hintText: 'school.blackboard.com',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add Domain'),
          ),
        ],
      ),
    );

    if (added != null && added.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Domain '$added' permitted for testing.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Classroom & Exam Fleet Orchestrator'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Roster',
            onPressed: _loadSessions,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? _buildEmptyState()
              : Row(
                  children: [
                    // Left Session Selector
                    SizedBox(
                      width: 280,
                      child: _buildSessionListSidebar(),
                    ),
                    const VerticalDivider(width: 1),
                    // Main Classroom Dashboard
                    Expanded(
                      child: _selectedSession == null
                          ? const Center(child: Text('Select an instructional session'))
                          : _buildClassroomMainView(isDark),
                    ),
                  ],
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.school_outlined, size: 64, color: Colors.grey[500]),
          const SizedBox(height: 16),
          const Text(
            'No Active Classroom Sessions',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('Start a class period to orchestrate student fleet devices.'),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () async {
              await _service.startClassroomSession(
                orgId: widget.orgId,
                unitId: 'unit_lincoln_high',
                fleetId: 'flt_cart_4b',
                classroomName: 'Biology 101 - Period 3',
              );
              _loadSessions();
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('Launch Biology 101 Period'),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionListSidebar() {
    return ListView.builder(
      itemCount: _sessions.length,
      itemBuilder: (context, idx) {
        final session = _sessions[idx];
        final isSelected = session.sessionId == _selectedSession?.sessionId;
        return ListTile(
          selected: isSelected,
          leading: Icon(
            session.mode == ClassroomFocusMode.strictExamMode
                ? Icons.lock
                : Icons.school,
            color: session.mode == ClassroomFocusMode.strictExamMode
                ? Colors.amber[800]
                : Colors.teal[600],
          ),
          title: Text(
            session.classroomName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${session.mode.displayName} • ${session.studentCount} devices',
          ),
          onTap: () {
            setState(() {
              _selectedSession = session;
            });
          },
        );
      },
    );
  }

  Widget _buildClassroomMainView(bool isDark) {
    final s = _selectedSession!;
    final isExam = s.mode == ClassroomFocusMode.strictExamMode;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card: Classroom Info & Timer
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.classroomName,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Teacher: ${s.teacherUserId}  •  Fleet: ${s.fleetId}  •  Unit: ${s.unitId}',
                              style: TextStyle(color: Colors.grey[600], fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      // Countdown Display
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isExam ? Colors.amber[900]?.withOpacity(0.15) : Colors.teal.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isExam ? Colors.amber[800]! : Colors.teal,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              color: isExam ? Colors.amber[800] : Colors.teal,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatSeconds(s.remainingSeconds),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: isExam ? Colors.amber[800] : Colors.teal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  // Mode Selector Row
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'Focus Mode:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      ChoiceChip(
                        label: const Text('Normal Protection'),
                        selected: s.mode == ClassroomFocusMode.normalProtection,
                        onSelected: (_) => _changeFocusMode(ClassroomFocusMode.normalProtection),
                      ),
                      ChoiceChip(
                        label: const Text('Restricted Research'),
                        selected: s.mode == ClassroomFocusMode.restrictedResearch,
                        onSelected: (_) => _changeFocusMode(ClassroomFocusMode.restrictedResearch),
                      ),
                      ChoiceChip(
                        label: const Text('Strict Exam Lockdown'),
                        selected: isExam,
                        selectedColor: Colors.amber[800]?.withOpacity(0.25),
                        onSelected: (_) => _toggleStrictExamLock(),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Permit Domain'),
                        onPressed: _showAddAllowedDomainDialog,
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800]),
                        icon: const Icon(Icons.stop, color: Colors.white, size: 18),
                        label: const Text('Conclude Period', style: TextStyle(color: Colors.white)),
                        onPressed: () async {
                          await _service.endClassroomSession(s.sessionId);
                          _loadSessions();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Attention Alert Banner if violations exist
          if (s.distractionAlertCount > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange[800]?.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[800]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange[800]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Attention Alert: ${s.distractionAlertCount} student distraction attempts '
                      'intercepted in real-time. Unauthorized domains were sinkholed.',
                      style: TextStyle(fontWeight: FontWeight.w600, color: Colors.orange[900]),
                    ),
                  ),
                ],
              ),
            ),

          // Student Device Roster Grid
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                'Student Roster Presence (${s.students.length} Devices Connected)',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                'Sub-50ms WebSocket Heartbeat Active',
                style: TextStyle(fontSize: 12, color: Colors.green[700], fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 320,
              mainAxisExtent: 140,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: s.students.length,
            itemBuilder: (context, idx) {
              final student = s.students[idx];
              return _buildStudentCard(student, isDark);
            },
          ),
          const SizedBox(height: 24),

          // Inviolable Life-Safety Guarantee Footer Notice
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blueGrey.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blueGrey.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined, size: 22, color: Colors.blueGrey),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Inviolable Life Safety Exemption: Emergency domains (911.gov, 112.gov, emergency.gov) '
                    'and OS background push services (Apple APNs, Google GCM) remain unconditionally '
                    'reachable across all classroom focus tiers and lock states.',
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey[700]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentCard(StudentDeviceModel student, bool isDark) {
    final hasDistraction = student.distractionCount > 0;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: student.handRaised
              ? Colors.amber[700]!
              : (hasDistraction ? Colors.red[300]! : Colors.grey.withOpacity(0.2)),
          width: student.handRaised ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  student.isLocked ? Icons.lock : Icons.laptop_chromebook,
                  size: 18,
                  color: student.isLocked ? Colors.amber[800] : Colors.teal[700],
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    student.studentName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (student.handRaised)
                  Tooltip(
                    message: 'Hand Raised',
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.amber,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.pan_tool, size: 12, color: Colors.black87),
                    ),
                  ),
              ],
            ),
            Text(
              '${student.studentId} • ${student.clientIp}',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            Row(
              children: [
                const Icon(Icons.public, size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    student.lastQueriedDomain.isEmpty ? 'Idle' : student.lastQueriedDomain,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: hasDistraction ? Colors.red[700] : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (hasDistraction)
              Text(
                '${student.distractionCount} Off-Task Intercepts',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red[700]),
              )
            else
              Text(
                'Active & Focused',
                style: TextStyle(fontSize: 10, color: Colors.green[700]),
              ),
          ],
        ),
      ),
    );
  }
}
