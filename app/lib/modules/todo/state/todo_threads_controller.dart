import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:messie_api/messie_api.dart' as api;

import '../../../core/feed/module_types.dart';
import '../../../modules/matrix/state/auth_view_model.dart';
import '../services/todo_repository.dart';

/// Stream of todo lists for the current backend user, refreshed periodically.
final todoListsStreamProvider = StreamProvider.autoDispose<List<api.TodoList>>((ref) async* {
  final repo = ref.read(todoRepositoryProvider);
  final controller = StreamController<List<api.TodoList>>();

  Timer? timer;
  Future<void> tick() async {
    try {
      // Ensure a session exists and JWT is present
      await ref.read(authControllerProvider.notifier).ensureBackendJwt();
      final lists = await repo.getListsForCurrentUser();
      debugPrint('[todo] fetched ${lists.length} lists');
      ref.read(todoLastErrorProvider.notifier).state = null;
      controller.add(lists);
    } catch (_) {
      final err = _;
      debugPrint('[todo] fetch lists failed: $err');
      ref.read(todoLastErrorProvider.notifier).state = err.toString();
      controller.add(const <api.TodoList>[]);
    }
  }

  // initial fetch
  Future.microtask(() => tick());
  // periodic refresh
  timer = Timer.periodic(const Duration(seconds: 10), (_) { tick(); });

  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });

  yield* controller.stream;
});

/// Maps todo lists to HomeThread entries for the Home feed.
final todoHomeThreadsProvider = Provider<List<HomeThread>>((ref) {
  final listsValue = ref.watch(todoListsStreamProvider);
  return listsValue.maybeWhen(
    data: (lists) {
      final mapped = lists
          .map((l) => HomeThread(
                module: 'todo',
                threadId: l.id,
                name: l.title,
                avatarUrl: null,
                bumpTs: (l.updatedAt ?? l.createdAt)?.millisecondsSinceEpoch,
                notificationCount: 0,
                highlightCount: 0,
                isMuted: false,
              ))
          .toList(growable: false);
      mapped.sort((a, b) {
        final at = a.bumpTs ?? 0;
        final bt = b.bumpTs ?? 0;
        final cmp = bt.compareTo(at);
        if (cmp != 0) return cmp;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return mapped;
    },
    orElse: () => const <HomeThread>[],
  );
});

/// Detail data sources
final todoListByIdProvider = FutureProvider.autoDispose.family<api.TodoList?, String>((ref, listId) async {
  final repo = ref.read(todoRepositoryProvider);
  return repo.getListById(listId);
});

final todoItemsByListIdProvider = FutureProvider.autoDispose.family<List<api.TodoItem>, String>((ref, listId) async {
  final repo = ref.read(todoRepositoryProvider);
  return repo.getItemsByListId(listId);
});

/// Exposes last Todo module error for diagnostics/UI.
final todoLastErrorProvider = StateProvider<String?>((ref) => null);
