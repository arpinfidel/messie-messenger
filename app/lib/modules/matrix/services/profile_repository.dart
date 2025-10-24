import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../bridge/messie_bridge.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository();
});

class ProfileRepository {
  final Map<String, MemberProfileData> _cache = <String, MemberProfileData>{};

  Future<MemberProfileData?> memberProfile({
    required String roomId,
    required String userId,
  }) async {
    final key = '$roomId::$userId';
    final cached = _cache[key];
    if (cached != null) return cached;
    final res = await rustMemberProfile(roomId: roomId, userId: userId);
    if (res.isOk && res.data != null) {
      _cache[key] = res.data!;
      return res.data;
    }
    return null;
  }
}

