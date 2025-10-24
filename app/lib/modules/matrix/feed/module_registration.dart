import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feed/module_types.dart';
import 'threads.dart';
import 'actions.dart';

final matrixModuleRegistrationProvider = Provider<ModuleRegistration>((ref) {
  return ModuleRegistration(
    id: 'matrix',
    provideThreads: (wref) => wref.watch(matrixHomeThreadsProvider),
    actionsFactory: (rref) => MatrixThreadActions(rref),
  );
});
