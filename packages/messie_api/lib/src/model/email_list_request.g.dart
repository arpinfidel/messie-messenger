// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'email_list_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EmailListRequest extends EmailListRequest {
  @override
  final String? mailbox;
  @override
  final BuiltList<String>? searchFlags;
  @override
  final String host;
  @override
  final int port;
  @override
  final String email;
  @override
  final String appPassword;

  factory _$EmailListRequest(
          [void Function(EmailListRequestBuilder)? updates]) =>
      (EmailListRequestBuilder()..update(updates))._build();

  _$EmailListRequest._(
      {this.mailbox,
      this.searchFlags,
      required this.host,
      required this.port,
      required this.email,
      required this.appPassword})
      : super._();
  @override
  EmailListRequest rebuild(void Function(EmailListRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EmailListRequestBuilder toBuilder() =>
      EmailListRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EmailListRequest &&
        mailbox == other.mailbox &&
        searchFlags == other.searchFlags &&
        host == other.host &&
        port == other.port &&
        email == other.email &&
        appPassword == other.appPassword;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, mailbox.hashCode);
    _$hash = $jc(_$hash, searchFlags.hashCode);
    _$hash = $jc(_$hash, host.hashCode);
    _$hash = $jc(_$hash, port.hashCode);
    _$hash = $jc(_$hash, email.hashCode);
    _$hash = $jc(_$hash, appPassword.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EmailListRequest')
          ..add('mailbox', mailbox)
          ..add('searchFlags', searchFlags)
          ..add('host', host)
          ..add('port', port)
          ..add('email', email)
          ..add('appPassword', appPassword))
        .toString();
  }
}

class EmailListRequestBuilder
    implements
        Builder<EmailListRequest, EmailListRequestBuilder>,
        EmailLoginRequestBuilder {
  _$EmailListRequest? _$v;

  String? _mailbox;
  String? get mailbox => _$this._mailbox;
  set mailbox(covariant String? mailbox) => _$this._mailbox = mailbox;

  ListBuilder<String>? _searchFlags;
  ListBuilder<String> get searchFlags =>
      _$this._searchFlags ??= ListBuilder<String>();
  set searchFlags(covariant ListBuilder<String>? searchFlags) =>
      _$this._searchFlags = searchFlags;

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

  EmailListRequestBuilder() {
    EmailListRequest._defaults(this);
  }

  EmailListRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _mailbox = $v.mailbox;
      _searchFlags = $v.searchFlags?.toBuilder();
      _host = $v.host;
      _port = $v.port;
      _email = $v.email;
      _appPassword = $v.appPassword;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(covariant EmailListRequest other) {
    _$v = other as _$EmailListRequest;
  }

  @override
  void update(void Function(EmailListRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EmailListRequest build() => _build();

  _$EmailListRequest _build() {
    _$EmailListRequest _$result;
    try {
      _$result = _$v ??
          _$EmailListRequest._(
            mailbox: mailbox,
            searchFlags: _searchFlags?.build(),
            host: BuiltValueNullFieldError.checkNotNull(
                host, r'EmailListRequest', 'host'),
            port: BuiltValueNullFieldError.checkNotNull(
                port, r'EmailListRequest', 'port'),
            email: BuiltValueNullFieldError.checkNotNull(
                email, r'EmailListRequest', 'email'),
            appPassword: BuiltValueNullFieldError.checkNotNull(
                appPassword, r'EmailListRequest', 'appPassword'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'searchFlags';
        _searchFlags?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'EmailListRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
