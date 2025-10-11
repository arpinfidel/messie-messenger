// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_todo_list.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpdateTodoList extends UpdateTodoList {
  @override
  final String title;
  @override
  final String description;

  factory _$UpdateTodoList([void Function(UpdateTodoListBuilder)? updates]) =>
      (UpdateTodoListBuilder()..update(updates))._build();

  _$UpdateTodoList._({required this.title, required this.description})
      : super._();
  @override
  UpdateTodoList rebuild(void Function(UpdateTodoListBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdateTodoListBuilder toBuilder() => UpdateTodoListBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateTodoList &&
        title == other.title &&
        description == other.description;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UpdateTodoList')
          ..add('title', title)
          ..add('description', description))
        .toString();
  }
}

class UpdateTodoListBuilder
    implements Builder<UpdateTodoList, UpdateTodoListBuilder> {
  _$UpdateTodoList? _$v;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _description;
  String? get description => _$this._description;
  set description(String? description) => _$this._description = description;

  UpdateTodoListBuilder() {
    UpdateTodoList._defaults(this);
  }

  UpdateTodoListBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _title = $v.title;
      _description = $v.description;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdateTodoList other) {
    _$v = other as _$UpdateTodoList;
  }

  @override
  void update(void Function(UpdateTodoListBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdateTodoList build() => _build();

  _$UpdateTodoList _build() {
    final _$result = _$v ??
        _$UpdateTodoList._(
          title: BuiltValueNullFieldError.checkNotNull(
              title, r'UpdateTodoList', 'title'),
          description: BuiltValueNullFieldError.checkNotNull(
              description, r'UpdateTodoList', 'description'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
