// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'email_login_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

abstract class EmailLoginRequestBuilder {
  void replace(EmailLoginRequest other);
  void update(void Function(EmailLoginRequestBuilder) updates);
  String? get host;
  set host(String? host);

  int? get port;
  set port(int? port);

  String? get email;
  set email(String? email);

  String? get appPassword;
  set appPassword(String? appPassword);
}

class _$$EmailLoginRequest extends $EmailLoginRequest {
  @override
  final String host;
  @override
  final int port;
  @override
  final String email;
  @override
  final String appPassword;

  factory _$$EmailLoginRequest(
          [void Function($EmailLoginRequestBuilder)? updates]) =>
      ($EmailLoginRequestBuilder()..update(updates))._build();

  _$$EmailLoginRequest._(
      {required this.host,
      required this.port,
      required this.email,
      required this.appPassword})
      : super._();
  @override
  $EmailLoginRequest rebuild(
          void Function($EmailLoginRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  $EmailLoginRequestBuilder toBuilder() =>
      $EmailLoginRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is $EmailLoginRequest &&
        host == other.host &&
        port == other.port &&
        email == other.email &&
        appPassword == other.appPassword;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, host.hashCode);
    _$hash = $jc(_$hash, port.hashCode);
    _$hash = $jc(_$hash, email.hashCode);
    _$hash = $jc(_$hash, appPassword.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'$EmailLoginRequest')
          ..add('host', host)
          ..add('port', port)
          ..add('email', email)
          ..add('appPassword', appPassword))
        .toString();
  }
}

class $EmailLoginRequestBuilder
    implements
        Builder<$EmailLoginRequest, $EmailLoginRequestBuilder>,
        EmailLoginRequestBuilder {
  _$$EmailLoginRequest? _$v;

  String? _host;
  String? get host => _$this._host;
  set host(covariant String? host) => _$this._host = host;

  int? _port;
  int? get port => _$this._port;
  set port(covariant int? port) => _$this._port = port;

  String? _email;
  String? get email => _$this._email;
  set email(covariant String? email) => _$this._email = email;

  String? _appPassword;
  String? get appPassword => _$this._appPassword;
  set appPassword(covariant String? appPassword) =>
      _$this._appPassword = appPassword;

  $EmailLoginRequestBuilder() {
    $EmailLoginRequest._defaults(this);
  }

  $EmailLoginRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _host = $v.host;
      _port = $v.port;
      _email = $v.email;
      _appPassword = $v.appPassword;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(covariant $EmailLoginRequest other) {
    _$v = other as _$$EmailLoginRequest;
  }

  @override
  void update(void Function($EmailLoginRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  $EmailLoginRequest build() => _build();

  _$$EmailLoginRequest _build() {
    final _$result = _$v ??
        _$$EmailLoginRequest._(
          host: BuiltValueNullFieldError.checkNotNull(
              host, r'$EmailLoginRequest', 'host'),
          port: BuiltValueNullFieldError.checkNotNull(
              port, r'$EmailLoginRequest', 'port'),
          email: BuiltValueNullFieldError.checkNotNull(
              email, r'$EmailLoginRequest', 'email'),
          appPassword: BuiltValueNullFieldError.checkNotNull(
              appPassword, r'$EmailLoginRequest', 'appPassword'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
