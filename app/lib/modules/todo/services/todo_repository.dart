import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:messie_api/messie_api.dart' as api;

import '../../../api/messie_api_provider.dart';
import '../../matrix/state/auth_view_model.dart';

final todoRepositoryProvider = Provider<TodoRepository>((ref) {
  return TodoRepository(ref);
});

class TodoRepository {
  TodoRepository(this._ref);
  final Ref _ref;

  api.DefaultApi get _api => _ref.read(messieApiProvider).getDefaultApi();

  Future<bool> _ensureAuth() async {
    await _ref.read(authControllerProvider.notifier).ensureBackendJwt();
    final session = _ref.read(authControllerProvider).asData?.value;
    return session?.backendJwt != null && session!.backendJwt!.isNotEmpty;
  }

  String? _backendUserId() {
    final session = _ref.read(authControllerProvider).asData?.value;
    return session?.backendUserId;
  }

  Future<List<api.TodoList>> getListsForCurrentUser() async {
    final ok = await _ensureAuth();
    if (!ok) {
      debugPrint('[todo] ensureAuth failed: missing backend JWT');
      throw StateError('Todo auth missing');
    }
    final uid = _backendUserId();
    if (uid == null || uid.isEmpty) {
      debugPrint('[todo] missing backend user id – cannot query lists');
      throw StateError('Todo backend user id missing');
    }
    try {
      final res = await _api.getTodoListsByUserId(userId: uid);
      final data = res.data;
      return data?.toList() ?? const <api.TodoList>[];
    } catch (e) {
      debugPrint('[todo] getTodoListsByUserId failed: $e');
      rethrow;
    }
  }

  Future<api.TodoList?> getListById(String listId) async {
    final ok = await _ensureAuth();
    if (!ok) return null;
    try {
      final res = await _api.getTodoListById(listId: listId);
      return res.data;
    } catch (e) {
      debugPrint('[todo] getTodoListById($listId) failed: $e');
      rethrow;
    }
  }

  Future<List<api.TodoItem>> getItemsByListId(String listId) async {
    final ok = await _ensureAuth();
    if (!ok) return const <api.TodoItem>[];
    try {
      final res = await _api.getTodoItemsByListId(listId: listId);
      final items = res.data?.toList() ?? const <api.TodoItem>[];
      items.sort((a, b) => (a.position).compareTo(b.position));
      return items;
    } catch (e) {
      debugPrint('[todo] getTodoItemsByListId($listId) failed: $e');
      rethrow;
    }
  }

  Future<api.TodoList?> createList({required String title, String description = ''}) async {
    final ok = await _ensureAuth();
    if (!ok) return null;
    final body = api.NewTodoList((b) => b
      ..title = title
      ..description = description);
    try {
      final res = await _api.createTodoList(newTodoList: body);
      return res.data;
    } catch (e) {
      debugPrint('[todo] createList failed: $e');
      rethrow;
    }
  }

  Future<api.TodoList?> updateList(String listId, {required String title, String description = ''}) async {
    final ok = await _ensureAuth();
    if (!ok) return null;
    final body = api.UpdateTodoList((b) => b
      ..title = title
      ..description = description);
    try {
      final res = await _api.updateTodoList(listId: listId, updateTodoList: body);
      return res.data;
    } catch (e) {
      debugPrint('[todo] updateList($listId) failed: $e');
      rethrow;
    }
  }

  Future<bool> deleteList(String listId) async {
    final ok = await _ensureAuth();
    if (!ok) return false;
    try {
      await _api.deleteTodoList(listId: listId);
    } catch (e) {
      debugPrint('[todo] deleteList($listId) failed: $e');
      rethrow;
    }
    return true;
  }

  Future<api.TodoItem?> createItem({
    required String listId,
    required String title,
    String description = '',
    bool completed = false,
    DateTime? dueDate,
    required String position,
  }) async {
    final ok = await _ensureAuth();
    if (!ok) return null;
    final body = api.NewTodoItem((b) => b
      ..listId = listId
      ..title = title
      ..description = description
      ..completed = completed
      ..dueDate = dueDate
      ..position = position);
    try {
      final res = await _api.createTodoItem(listId: listId, newTodoItem: body);
      return res.data;
    } catch (e) {
      debugPrint('[todo] createItem(list: $listId) failed: $e');
      rethrow;
    }
  }

  Future<api.TodoItem?> updateItem(
    String listId,
    String itemId, {
    required String title,
    String description = '',
    required bool completed,
    DateTime? dueDate,
    required String position,
  }) async {
    final ok = await _ensureAuth();
    if (!ok) return null;
    final body = api.UpdateTodoItem((b) => b
      ..title = title
      ..description = description
      ..completed = completed
      ..dueDate = dueDate
      ..position = position);
    try {
      final res = await _api.updateTodoItem(listId: listId, itemId: itemId, updateTodoItem: body);
      return res.data;
    } catch (e) {
      debugPrint('[todo] updateItem($itemId) failed: $e');
      rethrow;
    }
  }

  Future<bool> deleteItem(String listId, String itemId) async {
    final ok = await _ensureAuth();
    if (!ok) return false;
    try {
      await _api.deleteTodoItem(listId: listId, itemId: itemId);
    } catch (e) {
      debugPrint('[todo] deleteItem($itemId) failed: $e');
      rethrow;
    }
    return true;
  }
}
