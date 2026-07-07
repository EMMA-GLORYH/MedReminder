// lib/screens/connection_check_screen.dart

import 'package:flutter/material.dart';
import '../main.dart';

class ConnectionCheckScreen extends StatefulWidget {
  const ConnectionCheckScreen({super.key});

  @override
  State<ConnectionCheckScreen> createState() => _ConnectionCheckScreenState();
}

class _ConnectionCheckScreenState extends State<ConnectionCheckScreen> {
  String _status = 'Checking...';
  bool _isConnected = false;
  bool _isLoading = true;
  Map<String, bool> _tableChecks = {};

  @override
  void initState() {
    super.initState();
    _runHealthCheck();
  }

  Future<void> _runHealthCheck() async {
    setState(() {
      _isLoading = true;
      _status = 'Connecting to Supabase...';
      _tableChecks = {};
    });

    try {
      // ── Check 1: Basic Connection ──
      // Try to reach Supabase by querying profiles table
      await supabase.from('profiles').select('id').limit(1);

      setState(() {
        _status = 'Connected! Checking tables...';
      });

      // ── Check 2: Verify Each Table Exists ──
      final tables = [
        'profiles',
        'care_relationships',
        'medications',
        'medication_schedules',
        'dose_logs',
        'escalation_events',
      ];

      for (final table in tables) {
        try {
          await supabase.from(table).select('id').limit(1);
          setState(() {
            _tableChecks[table] = true;
          });
        } catch (e) {
          setState(() {
            _tableChecks[table] = false;
          });
        }
      }

      // ── Final Result ──
      final allPassed = !_tableChecks.containsValue(false);

      setState(() {
        _isConnected = allPassed;
        _isLoading = false;
        _status = allPassed
            ? 'All systems go!'
            : 'Some tables are missing or inaccessible';
      });
    } catch (e) {
      setState(() {
        _isConnected = false;
        _isLoading = false;
        _status = 'Connection failed: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Database Health Check'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 20),

            // ── Status Icon ──
            Icon(
              _isLoading
                  ? Icons.hourglass_top_rounded
                  : _isConnected
                  ? Icons.check_circle_rounded
                  : Icons.error_rounded,
              size: 80,
              color: _isLoading
                  ? Colors.orange
                  : _isConnected
                  ? Colors.green
                  : Colors.red,
            ),

            const SizedBox(height: 16),

            // ── Status Text ──
            Text(
              _status,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            // ── Table Check Results ──
            if (_tableChecks.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: _tableChecks.length,
                  itemBuilder: (context, index) {
                    final table = _tableChecks.keys.elementAt(index);
                    final passed = _tableChecks[table]!;

                    return Card(
                      child: ListTile(
                        leading: Icon(
                          passed
                              ? Icons.check_circle
                              : Icons.cancel,
                          color: passed ? Colors.green : Colors.red,
                        ),
                        title: Text(table),
                        subtitle: Text(
                          passed
                              ? 'Table found and accessible'
                              : 'Table missing or blocked by RLS',
                        ),
                      ),
                    );
                  },
                ),
              ),

            // ── Loading Indicator ──
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: CircularProgressIndicator(),
              ),

            // ── Retry Button ──
            if (!_isLoading)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: ElevatedButton.icon(
                  onPressed: _runHealthCheck,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Run Again'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}