import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

// Presence streaming is not wired yet. Keep controller as a no-op wrapper
// so UI code can depend on the provider without compilation errors.


final presenceControllerProvider =
    StateNotifierProvider<PresenceController, PresenceState>(
  (ref) => PresenceController(),
);

class PresenceController extends StateNotifier<PresenceState> {
  PresenceController() : super(PresenceState.initial());

  StreamSubscription<dynamic>? _subscription;
  String? _roomId;
  bool _starting = false;

  Future<void> start(String roomId) async {
    if (_starting) return;
    _starting = true;

    if (_roomId != roomId) {
      // Reset state when switching rooms
      _roomId = roomId;
      state = PresenceState(
          roomId: roomId, typingUserIds: const [], receipts: const {});
    }

    // Presence stream not available yet; no-op for now.
    _starting = false;
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _roomId = null;
    state = PresenceState.initial();
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
