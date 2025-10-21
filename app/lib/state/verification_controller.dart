import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/messie_bridge.dart';

final verificationControllerProvider =
    StateNotifierProvider<VerificationController, VerificationState>(
  (ref) => VerificationController(),
);

class VerificationController extends StateNotifier<VerificationState> {
  VerificationController() : super(const VerificationState.initial());

  ReceivePort? _port;
  StreamSubscription<dynamic>? _sub;

  Future<void> start({required String userId, String? deviceId}) async {
    await cancel();
    state = state.copyWith(
      active: true,
      status: 'requesting',
      error: null,
      emoji: const <String>[],
      flowId: null,
    );

    final start = await rustRequestSasVerification(userId: userId, deviceId: deviceId);
    if (!start.isOk || start.data == null || start.data!.flowId.isEmpty) {
      state = state.copyWith(
        active: false,
        status: 'error',
        error: start.error ?? 'Failed to start verification',
      );
      return;
    }

    final flowId = start.data!.flowId;
    state = state.copyWith(flowId: flowId, status: 'requested');

    _port = ReceivePort('messie_sas_$flowId');
    _sub = _port!.listen(_onMessage, onError: (Object e) {
      state = state.copyWith(error: e.toString());
    });
    final observe = await rustObserveSas(flowId: flowId, port: _port!.sendPort);
    if (!observe.isOk) {
      await _cleanupPort();
      state = state.copyWith(
        active: false,
        status: 'error',
        error: observe.error ?? 'Failed to observe SAS updates',
      );
      return;
    }
  }

  Future<void> confirm() async {
    final flowId = state.flowId;
    if (flowId == null) return;
    final res = await rustConfirmSas(flowId: flowId);
    if (!res.isOk) {
      state = state.copyWith(error: res.error ?? 'Failed to confirm');
    }
  }

  Future<void> cancel() async {
    final flowId = state.flowId;
    if (flowId != null) {
      final _ = await rustCancelSas(flowId: flowId);
    }
    await _cleanupPort();
    state = const VerificationState.initial();
  }

  Future<void> _cleanupPort() async {
    await _sub?.cancel();
    _sub = null;
    _port?.close();
    _port = null;
  }

  void _onMessage(dynamic message) {
    if (message is! String) return;
    try {
      final map = jsonDecode(message) as Map<String, dynamic>;
      if (map['kind'] != 'sas_update') return;
      final stateStr = (map['state'] as String?) ?? '';
      final emojis = (map['emoji'] as List?)?.map((e) => e.toString()).toList(growable: false) ?? const <String>[];
      final flowId = map['flow_id'] as String?;
      state = state.copyWith(
        status: stateStr,
        emoji: emojis,
        flowId: flowId ?? state.flowId,
      );
      if (stateStr == 'done' || stateStr == 'cancelled') {
        // Keep the final status visible but mark inactive and cleanup port.
        unawaited(_cleanupPort());
        state = state.copyWith(active: false);
      }
    } catch (_) {
      // ignore parse errors
    }
  }
}

class VerificationState {
  const VerificationState({
    required this.active,
    required this.status,
    required this.emoji,
    this.flowId,
    this.error,
  });

  const VerificationState.initial()
      : this(active: false, status: 'idle', emoji: const <String>[], flowId: null, error: null);

  final bool active;
  final String status; // requested | ready | keys_exchanged | confirmed | done | cancelled | error | requesting
  final List<String> emoji;
  final String? flowId;
  final String? error;

  VerificationState copyWith({
    bool? active,
    String? status,
    List<String>? emoji,
    String? flowId,
    String? error,
  }) {
    return VerificationState(
      active: active ?? this.active,
      status: status ?? this.status,
      emoji: emoji ?? this.emoji,
      flowId: flowId ?? this.flowId,
      error: error,
    );
  }
}
