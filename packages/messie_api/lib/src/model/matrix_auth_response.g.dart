// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'matrix_auth_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MatrixAuthResponse extends MatrixAuthResponse {
  @override
  final String token;
  @override
  final String mxid;
  @override
  final String userId;

  factory _$MatrixAuthResponse(
          [void Function(MatrixAuthResponseBuilder)? updates]) =>
      (MatrixAuthResponseBuilder()..update(updates))._build();

  _$MatrixAuthResponse._(
      {required this.token, required this.mxid, required this.userId})
      : super._();
  @override
  MatrixAuthResponse rebuild(
          void Function(MatrixAuthResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MatrixAuthResponseBuilder toBuilder() =>
      MatrixAuthResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MatrixAuthResponse &&
        token == other.token &&
        mxid == other.mxid &&
        userId == other.userId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, token.hashCode);
    _$hash = $jc(_$hash, mxid.hashCode);
    _$hash = $jc(_$hash, userId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MatrixAuthResponse')
          ..add('token', token)
          ..add('mxid', mxid)
          ..add('userId', userId))
        .toString();
  }
}

class MatrixAuthResponseBuilder
    implements Builder<MatrixAuthResponse, MatrixAuthResponseBuilder> {
  _$MatrixAuthResponse? _$v;

  String? _token;
  String? get token => _$this._token;
  set token(String? token) => _$this._token = token;

  String? _mxid;
  String? get mxid => _$this._mxid;
  set mxid(String? mxid) => _$this._mxid = mxid;

  String? _userId;
  String? get userId => _$this._userId;
  set userId(String? userId) => _$this._userId = userId;

  MatrixAuthResponseBuilder() {
    MatrixAuthResponse._defaults(this);
  }

  MatrixAuthResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _token = $v.token;
      _mxid = $v.mxid;
      _userId = $v.userId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MatrixAuthResponse other) {
    _$v = other as _$MatrixAuthResponse;
  }

  @override
  void update(void Function(MatrixAuthResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MatrixAuthResponse build() => _build();

  _$MatrixAuthResponse _build() {
    final _$result = _$v ??
        _$MatrixAuthResponse._(
          token: BuiltValueNullFieldError.checkNotNull(
              token, r'MatrixAuthResponse', 'token'),
          mxid: BuiltValueNullFieldError.checkNotNull(
              mxid, r'MatrixAuthResponse', 'mxid'),
          userId: BuiltValueNullFieldError.checkNotNull(
              userId, r'MatrixAuthResponse', 'userId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
