// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'matrix_open_id_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MatrixOpenIDRequest extends MatrixOpenIDRequest {
  @override
  final String accessToken;
  @override
  final String matrixServerName;

  factory _$MatrixOpenIDRequest(
          [void Function(MatrixOpenIDRequestBuilder)? updates]) =>
      (MatrixOpenIDRequestBuilder()..update(updates))._build();

  _$MatrixOpenIDRequest._(
      {required this.accessToken, required this.matrixServerName})
      : super._();
  @override
  MatrixOpenIDRequest rebuild(
          void Function(MatrixOpenIDRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MatrixOpenIDRequestBuilder toBuilder() =>
      MatrixOpenIDRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MatrixOpenIDRequest &&
        accessToken == other.accessToken &&
        matrixServerName == other.matrixServerName;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, accessToken.hashCode);
    _$hash = $jc(_$hash, matrixServerName.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MatrixOpenIDRequest')
          ..add('accessToken', accessToken)
          ..add('matrixServerName', matrixServerName))
        .toString();
  }
}

class MatrixOpenIDRequestBuilder
    implements Builder<MatrixOpenIDRequest, MatrixOpenIDRequestBuilder> {
  _$MatrixOpenIDRequest? _$v;

  String? _accessToken;
  String? get accessToken => _$this._accessToken;
  set accessToken(String? accessToken) => _$this._accessToken = accessToken;

  String? _matrixServerName;
  String? get matrixServerName => _$this._matrixServerName;
  set matrixServerName(String? matrixServerName) =>
      _$this._matrixServerName = matrixServerName;

  MatrixOpenIDRequestBuilder() {
    MatrixOpenIDRequest._defaults(this);
  }

  MatrixOpenIDRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _accessToken = $v.accessToken;
      _matrixServerName = $v.matrixServerName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MatrixOpenIDRequest other) {
    _$v = other as _$MatrixOpenIDRequest;
  }

  @override
  void update(void Function(MatrixOpenIDRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MatrixOpenIDRequest build() => _build();

  _$MatrixOpenIDRequest _build() {
    final _$result = _$v ??
        _$MatrixOpenIDRequest._(
          accessToken: BuiltValueNullFieldError.checkNotNull(
              accessToken, r'MatrixOpenIDRequest', 'accessToken'),
          matrixServerName: BuiltValueNullFieldError.checkNotNull(
              matrixServerName, r'MatrixOpenIDRequest', 'matrixServerName'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
