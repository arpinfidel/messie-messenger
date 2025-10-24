import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/feed/module_types.dart';
import '../../../core/feed/thread_actions.dart';

class TodoThreadActions implements ThreadActions {
  TodoThreadActions();

  @override
  bool get supportsMute => false;

  @override
  Future<void> open(BuildContext context, WidgetRef ref, HomeThread thread) async {
    // Navigate to Todo detail route
    if (!context.mounted) return;
    context.pushNamed('todo_detail', pathParameters: {'listId': thread.threadId});
  }

  @override
  Future<bool> toggleMute(BuildContext context, WidgetRef ref, HomeThread thread) async {
    return false;
  }
}
