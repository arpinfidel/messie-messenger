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
  final Map<String, String> _userInputValues = {};
  // Track selected flow id to render the right UI (qr vs pairing code)
  String _currentFlowId = '';
  String _currentProvider = 'whatsapp';

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

  void _startWA({String provider = 'whatsapp'}) async {
    final jwt = ref.read(authControllerProvider).asData?.value?.backendJwt; // backend JWT
    _svc ??= BridgesService(bearerToken: jwt);
    try {
      _currentProvider = provider;
      // Discover flows, then let the user pick (default to qr if present)
      final flows = await _svc!.getLoginFlows(provider: provider);
      String? flow;
      if (flows.isNotEmpty) {
        // Always show all options from the bridge
        flow = await _pickFlow(flows);
        if (flow == null) return; // canceled
      } else {
        // Fallback to QR if bridge doesn't advertise flows
        flow = 'qr';
      }
      _currentFlowId = flow;
      final step = await _svc!.startLogin(flow, provider: provider);
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
        } else if (type == 'user_input') {
          // Reset any previous input caching
          _userInputValues.clear();
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
            (c) => (c['provider'] as String?) == provider,
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

  Future<void> _submitUserInput(String processId, String stepId) async {
    try {
      final next = await _svc!.submitUserInput(
        processId: processId,
        stepId: stepId,
        fields: Map<String, String>.from(_userInputValues),
        provider: _currentProvider,
      );
      if (!mounted) return;
      final nextType = next['type'] as String?;
      setState(() {
        _loginStep = nextType == 'complete' ? null : next;
      });
      if (nextType == 'display_and_wait') {
        final nextProcessId = (next['login_id'] ?? next['process_id']) as String? ?? processId;
        final nextStepId = next['step_id'] as String? ?? stepId;
        // ignore: unawaited_futures
        _displayAndWaitLoop(nextProcessId, nextStepId);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to submit: $e')));
    }
  }

  Future<void> _displayAndWaitLoop(String processId, String stepId) async {
    while (mounted && !_stopAwaitLoop && _state != 'connected') {
      try {
        final next = await _svc!.submitDisplayAndWait(
          processId: processId,
          stepId: stepId,
          provider: _currentProvider,
        );
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

  Future<void> _disconnectWA({String provider = 'whatsapp'}) async {
    final jwt = ref.read(authControllerProvider).asData?.value?.backendJwt; // backend JWT
    _svc ??= BridgesService(bearerToken: jwt);
    try {
      await _svc!.logoutAll(provider: provider);
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
                trailing: ((c['status'] as String?) == 'connected')
                    ? ElevatedButton(
                        onPressed: () => _disconnectWA(
                          provider: (c['provider'] as String?) ?? 'whatsapp',
                        ),
                        child: const Text('Disconnect'),
                      )
                    : ElevatedButton(
                        onPressed: () => _startWA(
                          provider: (c['provider'] as String?) ?? 'whatsapp',
                        ),
                        child: const Text('Connect'),
                      ),
              ),
            if (_loginStep != null)
              Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Bridge Login',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      if (_loginStep!['type'] == 'display_and_wait') ...[
                        Builder(builder: (context) {
                          final dw = (_loginStep!['display_and_wait'] as Map?)?.cast<String, dynamic>();
                          final msg = dw?['message'] as String?;
                          final imgUrl = dw?['image_url'] as String?;
                          final data = dw?['data'] as String?;
                          return Column(
                            children: [
                              if (msg != null && msg.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(msg),
                                  ),
                                ),
                              if (imgUrl != null && imgUrl.isNotEmpty)
                                Center(
                                  child: Image.network(imgUrl, width: 220, height: 220, fit: BoxFit.contain),
                                )
                              else if (_currentFlowId == 'qr' && data != null && data.isNotEmpty)
                                Center(
                                  child: QrImageView(
                                    data: data,
                                    version: QrVersions.auto,
                                    size: 220,
                                  ),
                                )
                              else if (data != null && data.isNotEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surfaceVariant,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: SelectableText(
                                    data,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontFeatures: [FontFeature.tabularFigures()],
                                      fontFamily: 'monospace',
                                      fontSize: 20,
                                    ),
                                  ),
                                )
                              else
                                const Text('Follow instructions in your Matrix app.'),
                            ],
                          );
                        }),
                      ]
                      else if ((_loginStep!['type'] == 'user_input') &&
                          (_loginStep!['user_input']?['fields'] is List)) ...[
                        const SizedBox(height: 8),
                        for (final f in (_loginStep!['user_input']['fields'] as List))
                          Builder(builder: (context) {
                            final m = (f as Map).cast<String, dynamic>();
                            final id = (m['id'] as String?) ?? '';
                            final label = (m['label'] as String?) ?? id;
                            final secret = (m['secret'] as bool?) ?? false;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: TextFormField(
                                obscureText: secret,
                                decoration: InputDecoration(
                                  border: const OutlineInputBorder(),
                                  labelText: label,
                                ),
                                onChanged: (v) => _userInputValues[id] = v,
                              ),
                            );
                          }),
                        const SizedBox(height: 8),
                        Builder(builder: (context) {
                          final processId = (_loginStep!['login_id'] ?? _loginStep!['process_id']) as String?;
                          final stepId = _loginStep!['step_id'] as String?;
                          return Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton(
                              onPressed: (processId != null && stepId != null)
                                  ? () => _submitUserInput(processId, stepId)
                                  : null,
                              child: const Text('Continue'),
                            ),
                          );
                        }),
                      ] else ...[
                        const Text('Follow instructions in your Matrix app.'),
                      ],
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
