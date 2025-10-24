import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../modules/matrix/state/room_list_view_model.dart';

class HomeThread {
  const HomeThread({
    required this.module,
    required this.roomId,
    required this.name,
    this.avatarUrl,
    this.bumpTs,
    this.notificationCount = 0,
    this.highlightCount = 0,
    this.isMuted = false,
  });

  final String module; // 'matrix' | future modules
  final String roomId; // thread identifier for module
  final String name;
  final String? avatarUrl;
  final int? bumpTs;
  final int notificationCount;
  final int highlightCount;
  final bool isMuted;
}

/// Matrix-backed threads for Home list (MVP). Later: merge with other modules.
final homeThreadsProvider = Provider<List<HomeThread>>((ref) {
  final state = ref.watch(roomListControllerProvider);
  final rooms = <RoomPreview>[...state.hpRooms, ...state.lpRooms];
  return rooms
      .map((r) => HomeThread(
            module: 'matrix',
            roomId: r.roomId,
            name: r.name,
            avatarUrl: r.avatarUrl,
            bumpTs: r.bumpTs,
            notificationCount: r.notificationCount,
            highlightCount: r.highlightCount,
            isMuted: r.isMuted,
          ))
      .toList(growable: false);
});

