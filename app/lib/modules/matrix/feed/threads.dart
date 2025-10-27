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
            // Use only real event timestamps for Home ordering/display.
            // `r.bumpTs` maps to latest_event_ts (Unix ms). Do not fall back to
            // Matrix recency here because it is not an epoch timestamp and
            // renders confusing values in the UI. Rooms that lack a
            // latest_event_ts will temporarily sort lower until background
            // probes populate it, after which they jump to the correct spot.
            bumpTs: r.bumpTs,
            notificationCount: r.notificationCount,
            highlightCount: r.highlightCount,
            isMuted: r.isMuted,
          ))
      .toList(growable: false);
});
