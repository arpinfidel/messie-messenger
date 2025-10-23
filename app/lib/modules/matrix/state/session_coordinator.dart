import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_view_model.dart';
import '../../../services/counts_sync_service.dart';
import 'room_list_view_model.dart';
import 'timeline_view_model.dart';
import 'backup_view_model.dart';
import 'verification_view_model.dart';
import 'selection.dart';

/// Central coordinator for session-driven service lifecycles.
///
/// Listens to authentication session changes and starts/stops background
/// services and streams accordingly so that UI widgets remain side-effect free.
final sessionCoordinatorProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<MatrixSession?>>(authControllerProvider,
      (prev, next) {
    final session = next.asData?.value;

    final counts = ref.read(countsSyncProvider.notifier);
    final roomList = ref.read(roomListControllerProvider.notifier);
    final timeline = ref.read(timelineControllerProvider.notifier);
    final backup = ref.read(backupControllerProvider.notifier);
    final verification = ref.read(verificationControllerProvider.notifier);

    if (session != null) {
      counts.start(
        homeserverUrl: session.homeserverUrl,
        accessToken: session.accessToken,
        userId: session.userId,
      );
      roomList.start();
      backup.start();
    } else {
      counts.stop();
      roomList.stop();
      timeline.stop();
      backup.stop();
      verification.cancel();
      // Reset selection on logout
      ref.read(selectedRoomIdProvider.notifier).state = null;
    }
  });
});
