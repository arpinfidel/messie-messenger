// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'todo_list.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TodoList extends TodoList {
  @override
  final String id;
  @override
  final String ownerId;
  @override
  final String title;
  @override
  final String description;
  @override
  final DateTime? createdAt;
  @override
  final DateTime? updatedAt;

  factory _$TodoList([void Function(TodoListBuilder)? updates]) =>
      (TodoListBuilder()..update(updates))._build();

  _$TodoList._(
      {required this.id,
      required this.ownerId,
      required this.title,
      required this.description,
      this.createdAt,
      this.updatedAt})
      : super._();
  @override
  TodoList rebuild(void Function(TodoListBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TodoListBuilder toBuilder() => TodoListBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TodoList &&
        id == other.id &&
        ownerId == other.ownerId &&
        title == other.title &&
        description == other.description &&
        createdAt == other.createdAt &&
        updatedAt == other.updatedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, ownerId.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TodoList')
          ..add('id', id)
          ..add('ownerId', ownerId)
          ..add('title', title)
          ..add('description', description)
          ..add('createdAt', createdAt)
          ..add('updatedAt', updatedAt))
        .toString();
  }
}

class TodoListBuilder implements Builder<TodoList, TodoListBuilder> {
  _$TodoList? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _ownerId;
  String? get ownerId => _$this._ownerId;
  set ownerId(String? ownerId) => _$this._ownerId = ownerId;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _description;
  String? get description => _$this._description;
  set description(String? description) => _$this._description = description;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  TodoListBuilder() {
    TodoList._defaults(this);
  }

  TodoListBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _ownerId = $v.ownerId;
      _title = $v.title;
      _description = $v.description;
      _createdAt = $v.createdAt;
      _updatedAt = $v.updatedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TodoList other) {
    _$v = other as _$TodoList;
  }

  @override
  void update(void Function(TodoListBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TodoList build() => _build();

  _$TodoList _build() {
    final _$result = _$v ??
        _$TodoList._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'TodoList', 'id'),
          ownerId: BuiltValueNullFieldError.checkNotNull(
              ownerId, r'TodoList', 'ownerId'),
          title: BuiltValueNullFieldError.checkNotNull(
              title, r'TodoList', 'title'),
          description: BuiltValueNullFieldError.checkNotNull(
              description, r'TodoList', 'description'),
          createdAt: createdAt,
          updatedAt: updatedAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
