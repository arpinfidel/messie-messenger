import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'module_types.dart';
// Intentionally does not depend on module registry to avoid import cycles.

abstract class ThreadActions {
  bool get supportsMute => false;

  Future<void> open(BuildContext context, WidgetRef ref, HomeThread thread);

  Future<bool> toggleMute(BuildContext context, WidgetRef ref, HomeThread thread) async {
    return false;
  }
}

class NoopThreadActions implements ThreadActions {
  NoopThreadActions(this.module);
  final String module;

  @override
  Future<void> open(BuildContext context, WidgetRef ref, HomeThread thread) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text('Opening $module coming soon')));
  }

  @override
  bool get supportsMute => false;

  @override
  Future<bool> toggleMute(BuildContext context, WidgetRef ref, HomeThread thread) async {
    return false;
  }
}
