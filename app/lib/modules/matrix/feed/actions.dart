import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feed/module_types.dart';
import '../../../core/feed/thread_actions.dart';
import '../state/selection.dart';
import '../state/timeline_view_model.dart';
import '../services/room_repository.dart';
import '../state/room_list_view_model.dart';

class MatrixThreadActions implements ThreadActions {
  MatrixThreadActions(this._ref);
  final Ref _ref;

  @override
  bool get supportsMute => true;

  @override
  Future<void> open(BuildContext context, WidgetRef ref, HomeThread thread) async {
    // thread.threadId is the Matrix roomId
    _ref.read(selectedRoomIdProvider.notifier).state = thread.threadId;
    await _ref.read(timelineControllerProvider.notifier).openRoom(thread.threadId);
  }

  @override
  Future<bool> toggleMute(BuildContext context, WidgetRef ref, HomeThread thread) async {
    final ok = await _ref.read(roomRepositoryProvider).setMute(thread.threadId, !thread.isMuted);
    if (ok) {
      // Refresh subscriptions to reflect new mute state ordering if needed
      await _ref.read(roomListControllerProvider.notifier).resubscribeAll();
    }
    return ok;
  }
}
