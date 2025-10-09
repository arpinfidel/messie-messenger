import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/messie_bridge.dart';

const _presenceHandle = 'primary';

final presenceControllerProvider =
    StateNotifierProvider<PresenceController, PresenceState>(
  (ref) => PresenceController(),
);

class PresenceController extends StateNotifier<PresenceState> {
  PresenceController() : super(PresenceState.initial());

  ReceivePort? _receivePort;
  StreamSubscription<dynamic>? _subscription;
  String? _roomId;
  bool _starting = false;

  Future<void> start(String roomId) async {
    if (_starting) return;
    _starting = true;

    if (_roomId != roomId) {
      // Reset state when switching rooms
      _roomId = roomId;
      state = PresenceState(roomId: roomId, typingUserIds: const [], receipts: const {});
    }

    _receivePort?.close();
    await _subscription?.cancel();

    _receivePort = ReceivePort('messie_presence_$roomId');
    _subscription = _receivePort!.listen(_handleMessage, onError: (Object error) {
      // Presence is best-effort; keep state but drop the stream.
    });

    final streamResult = await rustPresenceStream(
      handle: _presenceHandle,
      roomId: roomId,
      port: _receivePort!.sendPort,
    );

    if (!streamResult.isOk) {
      await _subscription?.cancel();
      _subscription = null;
      _receivePort?.close();
      _receivePort = null;
    }

    _starting = false;
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _receivePort?.close();
    _receivePort = null;
    _roomId = null;
    state = PresenceState.initial();
  }

  void _handleMessage(dynamic message) {
    if (_roomId == null || message is! String) {
      return;
    }

    try {
      final decoded = jsonDecode(message) as Map<String, dynamic>;
      final kind = decoded['kind'] as String? ?? '';

      switch (kind) {
        case 'presence_ready':
          break; // no-op
        case 'presence_snapshot':
          final typing = (decoded['typing'] as List<dynamic>? ?? const <dynamic>[])
              .map((v) => v.toString())
              .toList(growable: false);
          state = state.copyWith(typingUserIds: typing);
          break;
        case 'receipt_update':
          final eventId = decoded['event_id'] as String?;
          if (eventId == null) break;
          final users = (decoded['user_ids'] as List<dynamic>? ?? const <dynamic>[])
              .map((v) => v.toString())
              .toSet();
          final receipts = Map<String, Set<String>>.from(state.receipts);
          final existing = receipts[eventId] ?? <String>{};
          receipts[eventId] = existing..addAll(users);
          state = state.copyWith(receipts: receipts);
          break;
        default:
          break;
      }
    } catch (_) {
      // ignore malformed updates
    }
  }
}

class PresenceState {
  const PresenceState({
    required this.roomId,
    required this.typingUserIds,
    required this.receipts,
  });

  factory PresenceState.initial() => const PresenceState(
        roomId: null,
        typingUserIds: [],
        receipts: {},
      );

  final String? roomId;
  final List<String> typingUserIds;
  final Map<String, Set<String>> receipts; // eventId -> userIds

  PresenceState copyWith({
    String? roomId,
    List<String>? typingUserIds,
    Map<String, Set<String>>? receipts,
  }) {
    return PresenceState(
      roomId: roomId ?? this.roomId,
      typingUserIds: typingUserIds ?? this.typingUserIds,
      receipts: receipts ?? this.receipts,
    );
  }
}

