// FocusDNS Enterprise SIEM Screen - RFC 5424 Syslog & Cloud SIEM Streamer

import 'package:flutter/material.dart';
import '../models/enterprise_models.dart';
import '../services/enterprise_service.dart';

class EnterpriseSiemScreen extends StatefulWidget {
  final EnterpriseService? service;

  const EnterpriseSiemScreen({super.key, this.service});

  @override
  State<EnterpriseSiemScreen> createState() => _EnterpriseSiemScreenState();
}

class _EnterpriseSiemScreenState extends State<EnterpriseSiemScreen> {
  late final EnterpriseService _service;
  bool _isLoading = true;
  SiemConfigModel? _config;
  String? _testResult;
  bool _isTesting = false;

  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _tokenController;
  late final TextEditingController _indexController;

  String _selectedTransport = 'UDP';
  int _minSeverity = 4;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? EnterpriseService();
    _hostController = TextEditingController();
    _portController = TextEditingController();
    _tokenController = TextEditingController();
    _indexController = TextEditingController();
    _loadConfig();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    _indexController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);
    try {
      final cfg = await _service.fetchSiemConfig();
      if (mounted) {
        setState(() {
          _config = cfg;
          _selectedTransport = cfg.transport;
          _minSeverity = cfg.minSeverity;
          _hostController.text = cfg.host;
          _portController.text = cfg.port.toString();
          _tokenController.text = cfg.apiToken;
          _indexController.text = cfg.indexName;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _runTestProbe() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });
    try {
      final success = await _service.testSiemConnection();
      if (mounted) {
        setState(() {
          _isTesting = false;
          _testResult = success
              ? 'SUCCESS: RFC 5424 test probe transmitted successfully.'
              : 'FAILURE: Unable to reach SIEM collector endpoint.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTesting = false;
          _testResult = 'ERROR: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141416),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E20),
        elevation: 0,
        title: const Text(
          'Enterprise SIEM Integration (RFC 5424)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loadConfig,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4DD0E1)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderStatusCard(),
                  const SizedBox(height: 16),
                  if (_testResult != null) _buildTestResultBanner(),
                  const SizedBox(height: 16),
                  _buildSettingsCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildHeaderStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2C2C2E)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF4DD0E1).withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cloud_sync, color: Color(0xFF4DD0E1), size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Automated SIEM Telemetry Streaming',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                SizedBox(height: 2),
                Text(
                  'Streams security drops and DGA/phishing catches to Splunk, Datadog & Elastic.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF888888)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestResultBanner() {
    final isSuccess = _testResult!.startsWith('SUCCESS');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSuccess ? const Color(0xFF4CAF50).withOpacity(0.15) : const Color(0xFFEF5350).withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isSuccess ? const Color(0xFF4CAF50) : const Color(0xFFEF5350)),
      ),
      child: Row(
        children: [
          Icon(isSuccess ? Icons.check_circle : Icons.error, color: isSuccess ? const Color(0xFF4CAF50) : const Color(0xFFEF5350), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _testResult!,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSuccess ? const Color(0xFF4CAF50) : const Color(0xFFEF5350)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C2C2E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Collector Protocol & Transport', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _selectedTransport,
            dropdownColor: const Color(0xFF1E1E20),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              filled: true,
              fillColor: Color(0xFF141416),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: ['UDP', 'TCP', 'TLS', 'SPLUNK_HEC', 'DATADOG_API', 'ELASTIC_BULK'].map((t) {
              return DropdownMenuItem(value: t, child: Text(t));
            }).toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedTransport = val);
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _hostController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Host / IP',
                    labelStyle: TextStyle(color: Color(0xFF888888)),
                    filled: true,
                    fillColor: Color(0xFF141416),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _portController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    labelStyle: TextStyle(color: Color(0xFF888888)),
                    filled: true,
                    fillColor: Color(0xFF141416),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _tokenController,
            obscureText: true,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'API / HEC Bearer Token',
              labelStyle: TextStyle(color: Color(0xFF888888)),
              filled: true,
              fillColor: Color(0xFF141416),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4DD0E1),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: _isTesting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.send, size: 16),
                  label: const Text('Send Test Probe'),
                  onPressed: _isTesting ? null : _runTestProbe,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
