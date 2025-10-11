// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'new_todo_list.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$NewTodoList extends NewTodoList {
  @override
  final String title;
  @override
  final String description;

  factory _$NewTodoList([void Function(NewTodoListBuilder)? updates]) =>
      (NewTodoListBuilder()..update(updates))._build();

  _$NewTodoList._({required this.title, required this.description}) : super._();
  @override
  NewTodoList rebuild(void Function(NewTodoListBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  NewTodoListBuilder toBuilder() => NewTodoListBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is NewTodoList &&
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
    return (newBuiltValueToStringHelper(r'NewTodoList')
          ..add('title', title)
          ..add('description', description))
        .toString();
  }
}

class NewTodoListBuilder implements Builder<NewTodoList, NewTodoListBuilder> {
  _$NewTodoList? _$v;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _description;
  String? get description => _$this._description;
  set description(String? description) => _$this._description = description;

  NewTodoListBuilder() {
    NewTodoList._defaults(this);
  }

  NewTodoListBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _title = $v.title;
      _description = $v.description;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(NewTodoList other) {
    _$v = other as _$NewTodoList;
  }

  @override
  void update(void Function(NewTodoListBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  NewTodoList build() => _build();

  _$NewTodoList _build() {
    final _$result = _$v ??
        _$NewTodoList._(
          title: BuiltValueNullFieldError.checkNotNull(
              title, r'NewTodoList', 'title'),
          description: BuiltValueNullFieldError.checkNotNull(
              description, r'NewTodoList', 'description'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
