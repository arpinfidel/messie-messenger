import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../bridge/messie_bridge.dart';

final roomRepositoryProvider = Provider<RoomRepository>((ref) {
  return RoomRepository();
});

class RoomRepository {
  Future<bool> setMute(String roomId, bool muted) async {
    final res = await rustSetRoomMute(roomId: roomId, muted: muted);
    return res.isOk;
  }
}

