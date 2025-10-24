import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feed/module_types.dart';
import '../../todo/state/todo_threads_controller.dart';
import 'actions.dart';

final todoModuleRegistrationProvider = Provider<ModuleRegistration>((ref) {
  return ModuleRegistration(
    id: 'todo',
    provideThreads: (wref) => wref.watch(todoHomeThreadsProvider),
    actionsFactory: (rref) => TodoThreadActions(),
  );
});
