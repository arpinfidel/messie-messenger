// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'todo_item.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TodoItem extends TodoItem {
  @override
  final String id;
  @override
  final String listId;
  @override
  final String title;
  @override
  final String description;
  @override
  final bool completed;
  @override
  final DateTime? dueDate;
  @override
  final DateTime? createdAt;
  @override
  final DateTime? updatedAt;
  @override
  final String position;

  factory _$TodoItem([void Function(TodoItemBuilder)? updates]) =>
      (TodoItemBuilder()..update(updates))._build();

  _$TodoItem._(
      {required this.id,
      required this.listId,
      required this.title,
      required this.description,
      required this.completed,
      this.dueDate,
      this.createdAt,
      this.updatedAt,
      required this.position})
      : super._();
  @override
  TodoItem rebuild(void Function(TodoItemBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TodoItemBuilder toBuilder() => TodoItemBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TodoItem &&
        id == other.id &&
        listId == other.listId &&
        title == other.title &&
        description == other.description &&
        completed == other.completed &&
        dueDate == other.dueDate &&
        createdAt == other.createdAt &&
        updatedAt == other.updatedAt &&
        position == other.position;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, listId.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jc(_$hash, completed.hashCode);
    _$hash = $jc(_$hash, dueDate.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jc(_$hash, position.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TodoItem')
          ..add('id', id)
          ..add('listId', listId)
          ..add('title', title)
          ..add('description', description)
          ..add('completed', completed)
          ..add('dueDate', dueDate)
          ..add('createdAt', createdAt)
          ..add('updatedAt', updatedAt)
          ..add('position', position))
        .toString();
  }
}

class TodoItemBuilder implements Builder<TodoItem, TodoItemBuilder> {
  _$TodoItem? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _listId;
  String? get listId => _$this._listId;
  set listId(String? listId) => _$this._listId = listId;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _description;
  String? get description => _$this._description;
  set description(String? description) => _$this._description = description;

  bool? _completed;
  bool? get completed => _$this._completed;
  set completed(bool? completed) => _$this._completed = completed;

  DateTime? _dueDate;
  DateTime? get dueDate => _$this._dueDate;
  set dueDate(DateTime? dueDate) => _$this._dueDate = dueDate;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  String? _position;
  String? get position => _$this._position;
  set position(String? position) => _$this._position = position;

  TodoItemBuilder() {
    TodoItem._defaults(this);
  }

  TodoItemBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _listId = $v.listId;
      _title = $v.title;
      _description = $v.description;
      _completed = $v.completed;
      _dueDate = $v.dueDate;
      _createdAt = $v.createdAt;
      _updatedAt = $v.updatedAt;
      _position = $v.position;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TodoItem other) {
    _$v = other as _$TodoItem;
  }

  @override
  void update(void Function(TodoItemBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TodoItem build() => _build();

  _$TodoItem _build() {
    final _$result = _$v ??
        _$TodoItem._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'TodoItem', 'id'),
          listId: BuiltValueNullFieldError.checkNotNull(
              listId, r'TodoItem', 'listId'),
          title: BuiltValueNullFieldError.checkNotNull(
              title, r'TodoItem', 'title'),
          description: BuiltValueNullFieldError.checkNotNull(
              description, r'TodoItem', 'description'),
          completed: BuiltValueNullFieldError.checkNotNull(
              completed, r'TodoItem', 'completed'),
          dueDate: dueDate,
          createdAt: createdAt,
          updatedAt: updatedAt,
          position: BuiltValueNullFieldError.checkNotNull(
              position, r'TodoItem', 'position'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
