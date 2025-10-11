// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'new_todo_item.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$NewTodoItem extends NewTodoItem {
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
  final String position;

  factory _$NewTodoItem([void Function(NewTodoItemBuilder)? updates]) =>
      (NewTodoItemBuilder()..update(updates))._build();

  _$NewTodoItem._(
      {required this.listId,
      required this.title,
      required this.description,
      required this.completed,
      this.dueDate,
      required this.position})
      : super._();
  @override
  NewTodoItem rebuild(void Function(NewTodoItemBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  NewTodoItemBuilder toBuilder() => NewTodoItemBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is NewTodoItem &&
        listId == other.listId &&
        title == other.title &&
        description == other.description &&
        completed == other.completed &&
        dueDate == other.dueDate &&
        position == other.position;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, listId.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jc(_$hash, completed.hashCode);
    _$hash = $jc(_$hash, dueDate.hashCode);
    _$hash = $jc(_$hash, position.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'NewTodoItem')
          ..add('listId', listId)
          ..add('title', title)
          ..add('description', description)
          ..add('completed', completed)
          ..add('dueDate', dueDate)
          ..add('position', position))
        .toString();
  }
}

class NewTodoItemBuilder implements Builder<NewTodoItem, NewTodoItemBuilder> {
  _$NewTodoItem? _$v;

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

  String? _position;
  String? get position => _$this._position;
  set position(String? position) => _$this._position = position;

  NewTodoItemBuilder() {
    NewTodoItem._defaults(this);
  }

  NewTodoItemBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _listId = $v.listId;
      _title = $v.title;
      _description = $v.description;
      _completed = $v.completed;
      _dueDate = $v.dueDate;
      _position = $v.position;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(NewTodoItem other) {
    _$v = other as _$NewTodoItem;
  }

  @override
  void update(void Function(NewTodoItemBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  NewTodoItem build() => _build();

  _$NewTodoItem _build() {
    final _$result = _$v ??
        _$NewTodoItem._(
          listId: BuiltValueNullFieldError.checkNotNull(
              listId, r'NewTodoItem', 'listId'),
          title: BuiltValueNullFieldError.checkNotNull(
              title, r'NewTodoItem', 'title'),
          description: BuiltValueNullFieldError.checkNotNull(
              description, r'NewTodoItem', 'description'),
          completed: BuiltValueNullFieldError.checkNotNull(
              completed, r'NewTodoItem', 'completed'),
          dueDate: dueDate,
          position: BuiltValueNullFieldError.checkNotNull(
              position, r'NewTodoItem', 'position'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
