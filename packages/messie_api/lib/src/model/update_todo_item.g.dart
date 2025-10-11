// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_todo_item.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpdateTodoItem extends UpdateTodoItem {
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

  factory _$UpdateTodoItem([void Function(UpdateTodoItemBuilder)? updates]) =>
      (UpdateTodoItemBuilder()..update(updates))._build();

  _$UpdateTodoItem._(
      {required this.title,
      required this.description,
      required this.completed,
      this.dueDate,
      required this.position})
      : super._();
  @override
  UpdateTodoItem rebuild(void Function(UpdateTodoItemBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdateTodoItemBuilder toBuilder() => UpdateTodoItemBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateTodoItem &&
        title == other.title &&
        description == other.description &&
        completed == other.completed &&
        dueDate == other.dueDate &&
        position == other.position;
  }

  @override
  int get hashCode {
    var _$hash = 0;
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
    return (newBuiltValueToStringHelper(r'UpdateTodoItem')
          ..add('title', title)
          ..add('description', description)
          ..add('completed', completed)
          ..add('dueDate', dueDate)
          ..add('position', position))
        .toString();
  }
}

class UpdateTodoItemBuilder
    implements Builder<UpdateTodoItem, UpdateTodoItemBuilder> {
  _$UpdateTodoItem? _$v;

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

  UpdateTodoItemBuilder() {
    UpdateTodoItem._defaults(this);
  }

  UpdateTodoItemBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
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
  void replace(UpdateTodoItem other) {
    _$v = other as _$UpdateTodoItem;
  }

  @override
  void update(void Function(UpdateTodoItemBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdateTodoItem build() => _build();

  _$UpdateTodoItem _build() {
    final _$result = _$v ??
        _$UpdateTodoItem._(
          title: BuiltValueNullFieldError.checkNotNull(
              title, r'UpdateTodoItem', 'title'),
          description: BuiltValueNullFieldError.checkNotNull(
              description, r'UpdateTodoItem', 'description'),
          completed: BuiltValueNullFieldError.checkNotNull(
              completed, r'UpdateTodoItem', 'completed'),
          dueDate: dueDate,
          position: BuiltValueNullFieldError.checkNotNull(
              position, r'UpdateTodoItem', 'position'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
