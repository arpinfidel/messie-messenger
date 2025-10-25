import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/feed/module_types.dart';
import '../../../core/feed/thread_actions.dart';

class EmailThreadActions implements ThreadActions {
  EmailThreadActions(this._ref);
  final Ref _ref;

  @override
  bool get supportsMute => false;

  @override
  Future<void> open(BuildContext context, WidgetRef ref, HomeThread thread) async {
    if (!context.mounted) return;
    context.pushNamed('email_detail', pathParameters: {'threadId': thread.threadId});
  }

  @override
  Future<bool> toggleMute(BuildContext context, WidgetRef ref, HomeThread thread) async {
    return false;
  }
}

