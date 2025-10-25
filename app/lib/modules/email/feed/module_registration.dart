import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feed/module_types.dart';
import '../state/email_threads_controller.dart';
import 'actions.dart';

final emailModuleRegistrationProvider = Provider<ModuleRegistration>((ref) {
  return ModuleRegistration(
    id: 'email',
    provideThreads: (wref) => wref.watch(emailHomeThreadsProvider),
    actionsFactory: (rref) => EmailThreadActions(rref),
  );
});

