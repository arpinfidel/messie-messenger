import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'module_types.dart';
import 'thread_actions.dart';
import '../../modules/matrix/feed/module_registration.dart';
import '../../modules/todo/feed/module_registration.dart';

// All module registrations in one place. Add new modules here.
final moduleRegistryProvider = Provider<List<ModuleRegistration>>((ref) {
  return <ModuleRegistration>[
    ref.watch(matrixModuleRegistrationProvider),
    ref.watch(todoModuleRegistrationProvider),
    // Future: emailModuleRegistrationProvider, …
  ];
});

class ThreadActionsRegistry {
  ThreadActionsRegistry(this._ref);
  final Ref _ref;

  ThreadActions forModule(String module) {
    final modules = _ref.read(moduleRegistryProvider);
    final found = modules.where((m) => m.id == module).cast<ModuleRegistration?>().firstWhere(
          (e) => e != null,
          orElse: () => null,
        );
    if (found != null) return found.actionsFactory(_ref);
    return NoopThreadActions(module);
  }
}

final threadActionsRegistryProvider = Provider<ThreadActionsRegistry>((ref) {
  return ThreadActionsRegistry(ref);
});

class ThreadNavigatorRegistry {
  ThreadNavigatorRegistry(this._ref);
  final Ref _ref;

  Future<void> navigate(BuildContext context, WidgetRef ref, HomeThread thread) async {
    final actions = ThreadActionsRegistry(_ref).forModule(thread.module);
    await actions.open(context, ref, thread);
  }

  HomeThreadNavigator navigatorFor(String module) {
    return (context, ref, thread) async {
      final actions = ThreadActionsRegistry(_ref).forModule(module);
      await actions.open(context, ref, thread);
    };
  }
}

final threadNavigatorRegistryProvider = Provider<ThreadNavigatorRegistry>((ref) {
  return ThreadNavigatorRegistry(ref);
});
