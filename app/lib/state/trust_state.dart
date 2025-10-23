import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../bridge/messie_bridge.dart';
import 'auth_controller.dart';

final selfTrustProvider = FutureProvider<TrustStateData?>((ref) async {
  final auth = ref.watch(authControllerProvider);
  final session = auth.asData?.value;
  if (session == null) return null;
  final res =
      await rustTrustState(userId: session.userId, deviceId: session.deviceId);
  if (!res.isOk) return null;
  return res.data;
});

