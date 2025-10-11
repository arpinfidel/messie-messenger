import 'dart:async';
import 'package:flutter/material.dart';
import 'package:messie_app/services/bridges_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:dio/dio.dart' show DioException;
// Display layer uses raw maps for now to avoid base URL issues in generated client.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart' show authControllerProvider;

class ConnectionsScreen extends ConsumerStatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  ConsumerState<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends ConsumerState<ConnectionsScreen> {
  BridgesService? _svc;
  late Future<List<Map<String, dynamic>>> _future;
  Map<String, dynamic>? _loginStep; // holds display_and_wait step with data
  String _state = 'not_connected';
  Timer? _poll;
  bool _stopAwaitLoop = false;

  @override
  void initState() {
    super.initState();
    _future = Future.value(const <Map<String, dynamic>>[]);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _stopAwaitLoop = true;
    super.dispose();
  }

  Future<String?> _pickFlow(List<Map<String, dynamic>> flows) async {
    if (!mounted) return null;
    return await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            children: [
              const ListTile(title: Text('Choose login method')),
              for (final f in flows)
                ListTile(
                  title: Text((f['name'] as String?) ?? (f['id'] as String? ?? 'flow')),
                  subtitle: (f['description'] != null) ? Text(f['description'] as String) : null,
                  onTap: () => Navigator.of(ctx).pop(f['id'] as String?),
                ),
            ],
          ),
        );
      },
    );
  }

  void _startWA() async {
    final jwt = ref.read(authControllerProvider).asData?.value?.backendJwt; // backend JWT
    _svc ??= BridgesService(bearerToken: jwt);
    try {
      // Discover flows, then let the user pick (default to qr if present)
      final flows = await _svc!.getLoginFlows();
      String flow = 'qr';
      if (flows.isNotEmpty) {
        final hasQr = flows.any((f) => (f['id'] ?? f['flow'] ?? '') == 'qr');
        if (!hasQr) {
          final choice = await _pickFlow(flows);
          if (choice == null) return; // canceled
          flow = choice;
        }
      }
      final step = await _svc!.startLogin(flow);
      // Handle either a typed WAStartResponse or a step-shaped response.
      final method = step['method'] as String?;
      if (method != null) {
        // WAStartResponse shape
        if (method == 'qr' && step['qrAscii'] is String && (step['qrAscii'] as String).isNotEmpty) {
          // Normalize to a display_and_wait shape for rendering only
          setState(() {
            _loginStep = {
              'type': 'display_and_wait',
              'display_and_wait': {'data': step['qrAscii']},
            };
            _state = 'pending';
          });
        } else {
          setState(() { _loginStep = null; _state = 'pending'; });
        }
        // We may not have step_id here; rely on periodic polling to detect connection.
      } else {
        // Step-shaped response
        setState(() { _loginStep = step; _state = 'pending'; });
      }

      // If the step is display_and_wait, start the long-poll loop so QR refreshes and progresses login.
      try {
        final type = step['type'] as String?;
        final processId = (step['login_id'] ?? step['process_id']) as String?;
        final stepId = step['step_id'] as String?;
        if (type == 'display_and_wait' && processId != null && stepId != null) {
          // ignore: unawaited_futures
          _displayAndWaitLoop(processId, stepId);
        }
      } catch (e) {
        // ignore: avoid_print
        print('failed to parse login step: $e');
      }
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
        bool connected = false;
        try {
          // Prefer backend aggregator; supports multi-account out of the box
          final conns = await _svc!.listConnections();
          final wa = conns.firstWhere(
            (c) => (c['provider'] as String?) == 'whatsapp',
            orElse: () => const {},
          );
          connected = (wa['status'] as String?) == 'connected';
        } catch (_) {}
        if (!mounted) return;
        if ((_state == 'connected' && connected) || (_state == 'pending' && !connected)) {
          // No change; avoid unnecessary rebuilds that may flicker the QR
        } else {
          setState(() { _state = connected ? 'connected' : 'pending'; });
        }
        if (connected) {
          _poll?.cancel();
          setState(() {
            _loginStep = null; // clear QR when connected
            _future = _svc!.listConnections();
          });
        }
      });
    } catch (e) {
      // Log detailed info for diagnostics
      // If it's a DioException, include URL, status, and body
      // ignore: avoid_print
      print('WA connect error: $e');
      // ignore: avoid_print
      if (e is DioException) {
        print('URL: ' + e.requestOptions.uri.toString());
        print('Status: ' + (e.response?.statusCode?.toString() ?? 'n/a'));
        print('Body: ' + (e.response?.data?.toString() ?? 'n/a'));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start connection: $e')),
      );
    }
  }

  Future<void> _displayAndWaitLoop(String processId, String stepId) async {
    while (mounted && !_stopAwaitLoop && _state != 'connected') {
      try {
        final next = await _svc!.submitDisplayAndWait(processId: processId, stepId: stepId);
        if (!mounted || _stopAwaitLoop) return;
        final nextType = next['type'] as String?;
        final nextStepId = next['step_id'] as String?;
        // Update QR only if the payload actually changed to avoid flicker
        if (nextType == 'display_and_wait') {
          final oldData = (_loginStep?['display_and_wait']?['data']) as String?;
          final newData = (next['display_and_wait']?['data']) as String?;
          if (newData != null && newData != oldData) {
            setState(() { _loginStep = next; });
          }
          if (nextStepId != null) {
            stepId = nextStepId;
          }
          // Continue loop to get further updates (QR rotate, scanned, etc.)
          continue;
        }
        // For other step types (user_input/cookies/complete), update view and exit loop.
        setState(() { _loginStep = nextType == 'complete' ? null : next; });
        break;
      } catch (e) {
        // ignore: avoid_print
        print('display_and_wait loop error: $e');
        // Brief backoff then retry unless canceled
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  Future<void> _disconnectWA() async {
    final jwt = ref.read(authControllerProvider).asData?.value?.backendJwt; // backend JWT
    _svc ??= BridgesService(bearerToken: jwt);
    try {
      await _svc!.logoutAll();
      setState(() {
        _state = 'not_connected';
        _loginStep = null;
        _future = _svc!.listConnections();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to disconnect: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final jwt = ref.watch(authControllerProvider).asData?.value?.backendJwt;
    if (jwt == null || jwt.isEmpty) {
      // Try to link backend JWT silently, then render a minimal UI.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(authControllerProvider.notifier).ensureBackendJwt();
      });
      return Scaffold(
        appBar: AppBar(title: const Text('Connections')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => ref.read(authControllerProvider.notifier).ensureBackendJwt(),
                child: const Text('Link to backend'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () async {
                  try {
                    _svc ??= BridgesService(bearerToken: jwt);
                    final ok = await _svc!.pingHealth();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backend health: $ok')));
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Health failed: $e')));
                  }
                },
                child: const Text('Ping backend /health'),
              ),
            ],
          ),
        ),
      );
    }
    _svc ??= BridgesService(bearerToken: jwt);
    _future = _svc!.listConnections();
    return Scaffold(
      appBar: AppBar(title: const Text('Connections')),
      body: FutureBuilder(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data ?? <Map<String, dynamic>>[];
          return ListView(children: [
            if (items.isEmpty)
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('whatsapp'),
                subtitle: const Text('not_connected'),
                trailing: ElevatedButton(
                  onPressed: _startWA,
                  child: const Text('Connect'),
                ),
              ),
            for (final c in items)
              ListTile(
                leading: const Icon(Icons.link),
                title: Text(c['provider'] as String? ?? ''),
                subtitle: Text(c['status'] as String? ?? ''),
                trailing: ((c['provider'] as String?) == 'whatsapp')
                    ? (((c['status'] as String?) == 'connected')
                        ? ElevatedButton(
                            onPressed: _disconnectWA,
                            child: const Text('Disconnect'),
                          )
                        : ElevatedButton(
                            onPressed: _startWA,
                            child: const Text('Connect'),
                          ))
                    : null,
              ),
            if (_loginStep != null)
              Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('WhatsApp Pairing',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      if ((_loginStep!['type'] == 'display_and_wait') &&
                          (_loginStep!['display_and_wait']?['data'] != null))
                        Center(
                          child: QrImageView(
                            data: _loginStep!['display_and_wait']['data'] as String,
                            version: QrVersions.auto,
                            size: 220,
                          ),
                        )
                      else
                        const Text('Follow instructions in your Matrix app.'),
                      const SizedBox(height: 8),
                      Text('Status: $_state'),
                    ],
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
