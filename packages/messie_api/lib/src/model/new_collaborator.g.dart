// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'new_collaborator.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$NewCollaborator extends NewCollaborator {
  @override
  final String userId;

  factory _$NewCollaborator([void Function(NewCollaboratorBuilder)? updates]) =>
      (NewCollaboratorBuilder()..update(updates))._build();

  _$NewCollaborator._({required this.userId}) : super._();
  @override
  NewCollaborator rebuild(void Function(NewCollaboratorBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  NewCollaboratorBuilder toBuilder() => NewCollaboratorBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is NewCollaborator && userId == other.userId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, userId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'NewCollaborator')
          ..add('userId', userId))
        .toString();
  }
}

class NewCollaboratorBuilder
    implements Builder<NewCollaborator, NewCollaboratorBuilder> {
  _$NewCollaborator? _$v;

  String? _userId;
  String? get userId => _$this._userId;
  set userId(String? userId) => _$this._userId = userId;

  NewCollaboratorBuilder() {
    NewCollaborator._defaults(this);
  }

  NewCollaboratorBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _userId = $v.userId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(NewCollaborator other) {
    _$v = other as _$NewCollaborator;
  }

  @override
  void update(void Function(NewCollaboratorBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  NewCollaborator build() => _build();

  _$NewCollaborator _build() {
    final _$result = _$v ??
        _$NewCollaborator._(
          userId: BuiltValueNullFieldError.checkNotNull(
              userId, r'NewCollaborator', 'userId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
