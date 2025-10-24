import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:messie_api/messie_api.dart' as api;

import '../../../modules/todo/state/todo_threads_controller.dart';
import '../../../modules/todo/services/todo_repository.dart';
import '../../../utils/fractional_index.dart';
import '../../../theme/messie_tokens.dart';
import '../../components/modal/adaptive_modal.dart';

class TodoDetailPage extends ConsumerStatefulWidget {
  const TodoDetailPage({super.key, required this.listId});
  final String listId;

  @override
  ConsumerState<TodoDetailPage> createState() => _TodoDetailPageState();
}

class _TodoDetailPageState extends ConsumerState<TodoDetailPage> {
  final _listTitleController = TextEditingController();
  final _listDescController = TextEditingController();
  final _newItemController = TextEditingController();

  final _listTitleFocus = FocusNode();
  final _listDescFocus = FocusNode();
  bool _editingTitle = false;
  bool _editingDesc = false;

  List<api.TodoItem> _items = const [];
  bool _dragging = false;

  @override
  void dispose() {
    _listTitleController.dispose();
    _listDescController.dispose();
    _newItemController.dispose();
    _listTitleFocus.dispose();
    _listDescFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = MessieSpacing.of(context);
    final listAsync = ref.watch(todoListByIdProvider(widget.listId));
    final itemsAsync = ref.watch(todoItemsByListIdProvider(widget.listId));
    final repo = ref.read(todoRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('To‑Do List')),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.gap.md, vertical: spacing.gap.md),
          child: listAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Failed to load: $e')),
            data: (list) {
              if (list == null) return const Center(child: Text('List not found'));

              // Only seed controllers when not editing
              if (!_editingTitle) _listTitleController.text = list.title;
              if (!_editingDesc) _listDescController.text = list.description;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title line (tap to edit)
                  _EditableLine(
                    controller: _listTitleController,
                    focusNode: _listTitleFocus,
                    textStyle: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    placeholder: 'List title',
                    editing: _editingTitle,
                    onTap: () => setState(() => _editingTitle = true),
                    onSubmitted: (value) async {
                      await _saveList(repo, list, title: value, description: _listDescController.text);
                      if (mounted) setState(() => _editingTitle = false);
                    },
                    onCanceled: () => setState(() => _editingTitle = false),
                  ),
                  SizedBox(height: spacing.gap.sm),
                  _EditableLine(
                    controller: _listDescController,
                    focusNode: _listDescFocus,
                    textStyle: Theme.of(context).textTheme.bodyMedium,
                    placeholder: 'Tap to add description',
                    maxLines: 3,
                    editing: _editingDesc,
                    onTap: () => setState(() => _editingDesc = true),
                    onSubmitted: (value) async {
                      await _saveList(repo, list, title: _listTitleController.text, description: value);
                      if (mounted) setState(() => _editingDesc = false);
                    },
                    onCanceled: () => setState(() => _editingDesc = false),
                  ),
                  SizedBox(height: spacing.gap.md),
                  Expanded(
                    child: itemsAsync.when(
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(child: Text('Failed to load items: $e')),
                      data: (items) {
                        // sync local list when not dragging
                        if (!_dragging) {
                          _items = List.of(items);
                        }
                        return _ReorderableItemsList(
                          items: _items,
                          onToggle: (item) async {
                            await repo.updateItem(
                              item.listId,
                              item.id,
                              title: item.title,
                              description: item.description,
                              completed: !item.completed,
                              dueDate: item.dueDate,
                              position: item.position,
                            );
                            if (!mounted) return;
                            ref.invalidate(todoItemsByListIdProvider(widget.listId));
                            ref.invalidate(todoListsStreamProvider);
                          },
                          onKebab: (ctx, item, index) => _showItemMenu(ctx, repo, item, index),
                          onReorderStart: () => setState(() => _dragging = true),
                          onReorderEnd: () => setState(() => _dragging = false),
                          onReorderPersist: (oldIndex, newIndex) async {
                            // Compute new fractional position
                            final newPrev = newIndex - 1 >= 0 ? _items[newIndex - 1].position : null;
                            final newNext = newIndex + 1 < _items.length ? _items[newIndex + 1].position : null;
                            final moved = _items[newIndex];
                            final newPos = generatePosition(newPrev, newNext);
                            await repo.updateItem(
                              moved.listId,
                              moved.id,
                              title: moved.title,
                              description: moved.description,
                              completed: moved.completed,
                              dueDate: moved.dueDate,
                              position: newPos,
                            );
                            if (!mounted) return;
                            ref.invalidate(todoItemsByListIdProvider(widget.listId));
                            ref.invalidate(todoListsStreamProvider);
                          },
                          onTitleCommit: (it, title) async {
                            await repo.updateItem(
                              it.listId,
                              it.id,
                              title: title,
                              description: it.description,
                              completed: it.completed,
                              dueDate: it.dueDate,
                              position: it.position,
                            );
                            if (!mounted) return;
                            ref.invalidate(todoItemsByListIdProvider(widget.listId));
                            ref.invalidate(todoListsStreamProvider);
                          },
                        );
                      },
                    ),
                  ),
                  SizedBox(height: spacing.gap.sm),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newItemController,
                          decoration: const InputDecoration(
                            hintText: 'Add a new todo item…',
                            isDense: true,
                          ),
                          onSubmitted: (_) => _addItem(repo),
                        ),
                      ),
                      SizedBox(width: spacing.gap.sm),
                      IconButton(
                        onPressed: () => _addItem(repo),
                        icon: const Icon(Icons.send_rounded),
                        tooltip: 'Add',
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _saveList(TodoRepository repo, api.TodoList list, {required String title, required String description}) async {
    final t = title.trim();
    if (t.isEmpty) return;
    await repo.updateList(list.id, title: t, description: description);
    if (!mounted) return;
    ref.invalidate(todoListByIdProvider(list.id));
    ref.invalidate(todoListsStreamProvider);
  }

  Future<void> _addItem(TodoRepository repo) async {
    final title = _newItemController.text.trim();
    if (title.isEmpty) return;
    final items = ref.read(todoItemsByListIdProvider(widget.listId)).maybeWhen(data: (d) => d, orElse: () => const <api.TodoItem>[]);
    final prev = items.isNotEmpty ? items.last.position : null;
    final position = generatePosition(prev, null);
    await repo.createItem(listId: widget.listId, title: title, position: position);
    _newItemController.clear();
    if (!mounted) return;
    ref.invalidate(todoItemsByListIdProvider(widget.listId));
    ref.invalidate(todoListsStreamProvider);
  }

  Future<void> _showItemMenu(BuildContext context, TodoRepository repo, api.TodoItem item, int index) async {
    final spacing = MessieSpacing.of(context);
    await showAdaptiveSheet<void>(
      context: context,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.gap.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_calendar_rounded),
                title: const Text('Edit details'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _showEditDetailsModal(context, repo, item);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                title: const Text('Delete'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await repo.deleteItem(item.listId, item.id);
                  if (!mounted) return;
                  ref.invalidate(todoItemsByListIdProvider(widget.listId));
                  ref.invalidate(todoListsStreamProvider);
                },
              ),
              SizedBox(height: spacing.gap.sm),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showEditDetailsModal(BuildContext context, TodoRepository repo, api.TodoItem item) async {
    DateTime? due = item.dueDate;
    final descController = TextEditingController(text: item.description);
    final spacing = MessieSpacing.of(context);
    await showAdaptiveModal<void>(
      context: context,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.all(spacing.gap.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Edit item', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              SizedBox(height: spacing.gap.md),
              TextField(
                controller: descController,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 3,
              ),
              SizedBox(height: spacing.gap.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event_rounded),
                      label: Text(due != null ? _formatDate(due!) : 'Set due date'),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: due ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          due = picked;
                        }
                      },
                    ),
                  ),
                  if (due != null) ...[
                    SizedBox(width: spacing.gap.sm),
                    IconButton(
                      tooltip: 'Clear',
                      onPressed: () { due = null; },
                      icon: const Icon(Icons.clear_rounded),
                    ),
                  ],
                ],
              ),
              SizedBox(height: spacing.gap.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Cancel'),
                  ),
                  SizedBox(width: spacing.gap.sm),
                  FilledButton(
                    onPressed: () async {
                      await repo.updateItem(
                        item.listId,
                        item.id,
                        title: item.title,
                        description: descController.text,
                        completed: item.completed,
                        dueDate: due,
                        position: item.position,
                      );
                      if (mounted) {
                        ref.invalidate(todoItemsByListIdProvider(widget.listId));
                        ref.invalidate(todoListsStreamProvider);
                      }
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

class _EditableLine extends StatefulWidget {
  const _EditableLine({
    required this.controller,
    required this.focusNode,
    required this.textStyle,
    required this.placeholder,
    required this.editing,
    required this.onTap,
    required this.onSubmitted,
    required this.onCanceled,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final TextStyle? textStyle;
  final String placeholder;
  final bool editing;
  final VoidCallback onTap;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onCanceled;
  final int maxLines;

  @override
  State<_EditableLine> createState() => _EditableLineState();
}

class _EditableLineState extends State<_EditableLine> {
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    if (!widget.editing) {
      final text = widget.controller.text.trim();
      return InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            text.isNotEmpty ? text : widget.placeholder,
            style: widget.textStyle?.copyWith(
              color: text.isNotEmpty ? null : color.onSurfaceVariant,
              fontStyle: text.isNotEmpty ? FontStyle.normal : FontStyle.italic,
            ),
          ),
        ),
      );
    }
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: true,
      maxLines: widget.maxLines,
      decoration: const InputDecoration(
        isDense: true,
        border: UnderlineInputBorder(),
        focusedBorder: UnderlineInputBorder(),
      ),
      style: widget.textStyle,
      onSubmitted: widget.onSubmitted,
      onEditingComplete: () => widget.onSubmitted(widget.controller.text),
    );
  }
}

class _ReorderableItemsList extends StatefulWidget {
  const _ReorderableItemsList({
    required this.items,
    required this.onToggle,
    required this.onKebab,
    required this.onReorderStart,
    required this.onReorderEnd,
    required this.onReorderPersist,
    required this.onTitleCommit,
  });

  final List<api.TodoItem> items;
  final void Function(api.TodoItem item) onToggle;
  final void Function(BuildContext ctx, api.TodoItem item, int index) onKebab;
  final VoidCallback onReorderStart;
  final VoidCallback onReorderEnd;
  final Future<void> Function(int oldIndex, int newIndex) onReorderPersist;
  final Future<void> Function(api.TodoItem item, String title) onTitleCommit;

  @override
  State<_ReorderableItemsList> createState() => _ReorderableItemsListState();
}

class _ReorderableItemsListState extends State<_ReorderableItemsList> {
  late List<api.TodoItem> _local;
  String? _editingId;
  final TextEditingController _titleController = TextEditingController();
  final FocusNode _titleFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _local = List.of(widget.items);
  }

  @override
  void didUpdateWidget(covariant _ReorderableItemsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.items.map((e) => e.id).toList(), widget.items.map((e) => e.id).toList())) {
      _local = List.of(widget.items);
    } else {
      // keep local ordering
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = MessieSpacing.of(context);
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      onReorderStart: (_) => widget.onReorderStart(),
      onReorderEnd: (_) => widget.onReorderEnd(),
      onReorder: (oldIndex, newIndex) async {
        // Adjust for flutter reordering semantics
        if (newIndex > oldIndex) newIndex -= 1;
        setState(() {
          final item = _local.removeAt(oldIndex);
          _local.insert(newIndex, item);
        });
        await widget.onReorderPersist(oldIndex, newIndex);
      },
      padding: EdgeInsets.zero,
      itemCount: _local.length,
      itemBuilder: (ctx, i) {
        final item = _local[i];
        return Container(
          key: ValueKey(item.id),
          padding: EdgeInsets.symmetric(vertical: spacing.gap.xs, horizontal: spacing.gap.xs),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: i,
                child: const Icon(Icons.drag_handle_rounded),
              ),
              Checkbox(
                value: item.completed,
                onChanged: (_) => widget.onToggle(item),
                visualDensity: VisualDensity.compact,
              ),
              Expanded(child: _buildTitleCell(context, item)),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: () => widget.onKebab(ctx, item, i),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTitleCell(BuildContext context, api.TodoItem item) {
    final isEditing = _editingId == item.id;
    if (!isEditing) {
      return InkWell(
        onTap: () {
          setState(() {
            _editingId = item.id;
            _titleController.text = item.title;
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    return TextField(
      controller: _titleController,
      focusNode: _titleFocus,
      autofocus: true,
      decoration: const InputDecoration(
        isDense: true,
        border: UnderlineInputBorder(),
        focusedBorder: UnderlineInputBorder(),
      ),
      onSubmitted: (value) async {
        final v = value.trim();
        if (v.isNotEmpty) {
          await widget.onTitleCommit(item, v);
        }
        if (mounted) setState(() => _editingId = null);
      },
      onEditingComplete: () async {
        final v = _titleController.text.trim();
        if (v.isNotEmpty) {
          await widget.onTitleCommit(item, v);
        }
        if (mounted) setState(() => _editingId = null);
      },
    );
  }
}
