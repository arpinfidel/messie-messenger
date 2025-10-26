import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../matrix/state/room_list_view_model.dart';
import '../../../core/feed/module_types.dart';

/// Matrix-backed threads adapter
final matrixHomeThreadsProvider = Provider<List<HomeThread>>((ref) {
  final state = ref.watch(roomListControllerProvider);
  final rooms = <RoomPreview>[...state.hpRooms, ...state.lpRooms];
  return rooms
      .map((r) => HomeThread(
            module: 'matrix',
            threadId: r.roomId,
            name: r.name,
            avatarUrl: r.avatarUrl,
            // Prefer real latest_event_ts; fall back to Matrix recency when missing.
            // This keeps ordering close to Element during initial hydration.
            bumpTs: r.bumpTs ?? r.recency,
            notificationCount: r.notificationCount,
            highlightCount: r.highlightCount,
            isMuted: r.isMuted,
          ))
      .toList(growable: false);
});
