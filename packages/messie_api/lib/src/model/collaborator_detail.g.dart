// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collaborator_detail.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CollaboratorDetail extends CollaboratorDetail {
  @override
  final String listId;
  @override
  final String username;
  @override
  final String collaboratorId;

  factory _$CollaboratorDetail(
          [void Function(CollaboratorDetailBuilder)? updates]) =>
      (CollaboratorDetailBuilder()..update(updates))._build();

  _$CollaboratorDetail._(
      {required this.listId,
      required this.username,
      required this.collaboratorId})
      : super._();
  @override
  CollaboratorDetail rebuild(
          void Function(CollaboratorDetailBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CollaboratorDetailBuilder toBuilder() =>
      CollaboratorDetailBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CollaboratorDetail &&
        listId == other.listId &&
        username == other.username &&
        collaboratorId == other.collaboratorId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, listId.hashCode);
    _$hash = $jc(_$hash, username.hashCode);
    _$hash = $jc(_$hash, collaboratorId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CollaboratorDetail')
          ..add('listId', listId)
          ..add('username', username)
          ..add('collaboratorId', collaboratorId))
        .toString();
  }
}

class CollaboratorDetailBuilder
    implements Builder<CollaboratorDetail, CollaboratorDetailBuilder> {
  _$CollaboratorDetail? _$v;

  String? _listId;
  String? get listId => _$this._listId;
  set listId(String? listId) => _$this._listId = listId;

  String? _username;
  String? get username => _$this._username;
  set username(String? username) => _$this._username = username;

  String? _collaboratorId;
  String? get collaboratorId => _$this._collaboratorId;
  set collaboratorId(String? collaboratorId) =>
      _$this._collaboratorId = collaboratorId;

  CollaboratorDetailBuilder() {
    CollaboratorDetail._defaults(this);
  }

  CollaboratorDetailBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _listId = $v.listId;
      _username = $v.username;
      _collaboratorId = $v.collaboratorId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CollaboratorDetail other) {
    _$v = other as _$CollaboratorDetail;
  }

  @override
  void update(void Function(CollaboratorDetailBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CollaboratorDetail build() => _build();

  _$CollaboratorDetail _build() {
    final _$result = _$v ??
        _$CollaboratorDetail._(
          listId: BuiltValueNullFieldError.checkNotNull(
              listId, r'CollaboratorDetail', 'listId'),
          username: BuiltValueNullFieldError.checkNotNull(
              username, r'CollaboratorDetail', 'username'),
          collaboratorId: BuiltValueNullFieldError.checkNotNull(
              collaboratorId, r'CollaboratorDetail', 'collaboratorId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
