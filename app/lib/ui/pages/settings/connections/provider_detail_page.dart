import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../components/card.dart';
import '../../../components/button.dart';
import '../../../components/chip.dart';
import 'package:messie_app/main.dart' show authControllerProvider; // to read backend JWT
import 'package:messie_app/services/bridges_service.dart';

enum ConnectMethod { qr, pairing }

class ProviderDetailPage extends ConsumerStatefulWidget {
  final String provider;
  const ProviderDetailPage({super.key, required this.provider});

  @override
  ConsumerState<ProviderDetailPage> createState() => _ProviderDetailPageState();
}

class _ProviderDetailPageState extends ConsumerState<ProviderDetailPage> {
  MessieStatus _status = MessieStatus.notConnected;

  BridgesService? _svc;
  Timer? _poll;
  bool _stopAwaitLoop = false;

  // Tracks active login flow and step
  String? _flowId; // 'qr' | 'pairing'
  Map<String, dynamic>? _loginStep; // current step (e.g., display_and_wait)
  final Map<String, String> _userInputValues = {};
  bool _didInitialStatusFetch = false;

  @override
  void dispose() {
    _poll?.cancel();
    _stopAwaitLoop = true;
    super.dispose();
  }

  Future<String?> _chooseFlow() async {
    // Fetch available flows then let the user pick one.
    try {
      final flows = await _svc!.getLoginFlows(provider: widget.provider);
      if (!mounted) return null;
      if (flows.isEmpty) {
        // Default to QR if bridge doesn't advertise flows
        return 'qr';
      }
      return await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
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
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _startConnect() async {
    final jwt = ref.read(authControllerProvider).asData?.value?.backendJwt;
    _svc ??= BridgesService(bearerToken: jwt);

    try {
      final flow = await _chooseFlow();
      if (flow == null) return; // user canceled or failed
      _flowId = flow;
      setState(() {
        _status = MessieStatus.pending;
        _loginStep = null; // ensure UI hides placeholders until data arrives
      });

      final Map<String, dynamic> step = await _svc!.startLogin(flow, provider: widget.provider);

      // Some bridges respond with a custom WAStartResponse (e.g., { method, qrAscii, code }).
      // Normalize it to a display_and_wait step so the UI can render uniformly.
      Map<String, dynamic>? normalized;
      final method = step['method'] as String?;
      final qrAscii = step['qrAscii'] as String?;
      final code = step['code'] as String?;
      if (method == 'qr' && qrAscii != null && qrAscii.isNotEmpty) {
        normalized = {
          'type': 'display_and_wait',
          'display_and_wait': {'data': qrAscii},
        };
      } else if ((method == 'pairing' || method == 'code') && code != null && code.isNotEmpty) {
        normalized = {
          'type': 'display_and_wait',
          'display_and_wait': {'data': code},
        };
      }

      setState(() {
        _loginStep = normalized ?? step;
      });

      // If the step is complete, flip status immediately
      final firstType = (_loginStep ?? step)['type'] as String?;
      if (firstType == 'complete') {
        if (!mounted) return;
        setState(() { _status = MessieStatus.connected; _loginStep = null; });
        return;
      }

      // If the step is display_and_wait, start long-poll for updates
      final type = firstType;
      final processId = ((_loginStep ?? step)['login_id'] ?? (_loginStep ?? step)['process_id']) as String?;
      final stepId = (_loginStep ?? step)['step_id'] as String?;
      if (type == 'display_and_wait' && processId != null && stepId != null) {
        // ignore: unawaited_futures
        _displayAndWaitLoop(processId, stepId);
      } else if (type == 'user_input') {
        _userInputValues.clear();
      }

      // Poll overall connection status
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
        try {
          final who = await _svc!.whoami(provider: widget.provider);
          final logins = (who['logins'] as List?) ?? const [];
          final connected = logins.isNotEmpty;
          if (!mounted) return;
          if (connected) {
            setState(() {
              _status = MessieStatus.connected;
              _loginStep = null; // clear UI once connected
            });
            _poll?.cancel();
          }
        } catch (_) {}
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start connection: $e')),
      );
      setState(() => _status = MessieStatus.notConnected);
    }
  }

  Future<void> _displayAndWaitLoop(String processId, String stepId) async {
    _stopAwaitLoop = false;
    while (mounted && !_stopAwaitLoop && _status != MessieStatus.connected) {
      try {
        final next = await _svc!.submitDisplayAndWait(
          processId: processId,
          stepId: stepId,
          provider: widget.provider,
        );
        if (!mounted) return;
        setState(() {
          _loginStep = next;
        });
        // Continue until connected; backend polling above will stop us
      } catch (_) {
        // best-effort; wait then retry
      }
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final jwt = ref.watch(authControllerProvider).asData?.value?.backendJwt;

    // Initialize service when JWT becomes available
    if (_svc == null && jwt != null && jwt.isNotEmpty) {
      _svc = BridgesService(bearerToken: jwt);
    }

    // One-time status fetch when opening the screen
    if (!_didInitialStatusFetch && _svc != null) {
      _didInitialStatusFetch = true;
      // ignore: discarded_futures
      Future(() async {
        try {
          final who = await _svc!.whoami(provider: widget.provider);
          final logins = (who['logins'] as List?) ?? const [];
          final connected = logins.isNotEmpty;
          if (!mounted) return;
          setState(() {
            _status = connected ? MessieStatus.connected : MessieStatus.notConnected;
          });
        } catch (_) {}
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.provider)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Status & Actions
          MessieCard(
            child: Row(
              children: [
                MessieStatusChip(status: _status),
                const Spacer(),
                if (_status == MessieStatus.connected)
                  MessieButton(
                    variant: MessieButtonVariant.secondary,
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await _svc?.logoutAll(provider: widget.provider);
                        if (!mounted) return;
                        setState(() => _status = MessieStatus.notConnected);
                      } catch (e) {
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(content: Text('Failed to disconnect: $e')),
                        );
                      }
                    },
                    child: const Text('Disconnect'),
                  )
                else
                  MessieButton(
                    onPressed: (jwt == null || jwt.isEmpty) ? null : _startConnect,
                    child: const Text('Connect'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 2. Connect UI (only while actively connecting)
          if (_status == MessieStatus.pending)
            MessieCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Connect', style: text.titleMedium),
                  const SizedBox(height: 12),
          Builder(builder: (context) {
            // Hide/blur until we have real data
            final stepType = _loginStep?['type'] as String?;
            final isDisplay = stepType == 'display_and_wait';
            final dw = (_loginStep?['display_and_wait'] as Map?)?.cast<String, dynamic>();
            final data = dw?['data'] as String?; // QR data or pairing code

            // Handle user_input: render fields + Continue
            if (stepType == 'user_input' && (_loginStep?['user_input']?['fields'] is List)) {
              final fields = (_loginStep!['user_input']['fields'] as List);
              return Column(
                children: [
                  for (final f in fields)
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
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: () {
                        final processId = (_loginStep!['login_id'] ?? _loginStep!['process_id']) as String?;
                        final stepId = _loginStep!['step_id'] as String?;
                        if (processId != null && stepId != null) {
                          _submitUserInput(processId, stepId);
                        }
                      },
                      child: const Text('Continue'),
                    ),
                  ),
                ],
              );
            }

            if (!isDisplay) {
              // Either waiting for first step or different step; avoid showing fake QR
              return Container(
                height: 220,
                alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const SizedBox(
                          height: 32,
                          width: 32,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                      );
                    }

                    // Show real QR or pairing code depending on chosen flow
                    if (_flowId == 'qr' && data != null && data.isNotEmpty) {
                      return Center(
                        child: QrImageView(
                          data: data,
                          version: QrVersions.auto,
                          size: 220,
                        ),
                      );
                    }
                    if (data != null && data.isNotEmpty) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SelectableText(
                          data,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 20),
                        ),
                      );
                    }

                    // Data missing; keep placeholder but blurred
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: Container(
                          height: 220,
                          alignment: Alignment.center,
                          color: Theme.of(context).colorScheme.surfaceContainerHigh,
                          child: const SizedBox(
                            height: 32,
                            width: 32,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          const SizedBox(height: 12),

          // 3. Troubleshooting
          MessieCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Troubleshooting', style: text.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'Use Connect to choose QR or Pairing code. If one fails, disconnect and try the other. Ensure your bridge is reachable and time is synchronized.',
                  style: text.bodySmall,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {},
                  child: const Text('Get help'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitUserInput(String processId, String stepId) async {
    try {
      final next = await _svc!.submitUserInput(
        processId: processId,
        stepId: stepId,
        fields: Map<String, String>.from(_userInputValues),
        provider: widget.provider,
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
      } else if (nextType == 'complete') {
        setState(() { _status = MessieStatus.connected; });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to submit: $e')));
    }
  }
}
