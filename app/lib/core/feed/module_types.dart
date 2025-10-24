import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'thread_actions.dart';

class HomeThread {
  const HomeThread({
    required this.module,
    required this.threadId,
    required this.name,
    this.avatarUrl,
    this.bumpTs,
    this.notificationCount = 0,
    this.highlightCount = 0,
    this.isMuted = false,
  });

  final String module; // e.g. 'matrix' | 'email' | 'todo'
  final String threadId; // identifier within the module
  final String name;
  final String? avatarUrl;
  final int? bumpTs; // unix ms
  final int notificationCount;
  final int highlightCount;
  final bool isMuted;
}

/// A module registration describes how a module contributes to the Home feed
/// and how to navigate/act on its threads.
class ModuleRegistration {
  const ModuleRegistration({
    required this.id,
    required this.provideThreads,
    required this.actionsFactory,
  });

  final String id;
  final List<HomeThread> Function(Ref ref) provideThreads;
  final ThreadActions Function(Ref ref) actionsFactory;
}

typedef HomeThreadNavigator = Future<void> Function(
  BuildContext context,
  WidgetRef ref,
  HomeThread thread,
);
