// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'login_step_cookies_cookies.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LoginStepCookiesCookies extends LoginStepCookiesCookies {
  @override
  final BuiltList<String>? names;

  factory _$LoginStepCookiesCookies(
          [void Function(LoginStepCookiesCookiesBuilder)? updates]) =>
      (LoginStepCookiesCookiesBuilder()..update(updates))._build();

  _$LoginStepCookiesCookies._({this.names}) : super._();
  @override
  LoginStepCookiesCookies rebuild(
          void Function(LoginStepCookiesCookiesBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LoginStepCookiesCookiesBuilder toBuilder() =>
      LoginStepCookiesCookiesBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LoginStepCookiesCookies && names == other.names;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, names.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LoginStepCookiesCookies')
          ..add('names', names))
        .toString();
  }
}

class LoginStepCookiesCookiesBuilder
    implements
        Builder<LoginStepCookiesCookies, LoginStepCookiesCookiesBuilder> {
  _$LoginStepCookiesCookies? _$v;

  ListBuilder<String>? _names;
  ListBuilder<String> get names => _$this._names ??= ListBuilder<String>();
  set names(ListBuilder<String>? names) => _$this._names = names;

  LoginStepCookiesCookiesBuilder() {
    LoginStepCookiesCookies._defaults(this);
  }

  LoginStepCookiesCookiesBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _names = $v.names?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LoginStepCookiesCookies other) {
    _$v = other as _$LoginStepCookiesCookies;
  }

  @override
  void update(void Function(LoginStepCookiesCookiesBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LoginStepCookiesCookies build() => _build();

  _$LoginStepCookiesCookies _build() {
    _$LoginStepCookiesCookies _$result;
    try {
      _$result = _$v ??
          _$LoginStepCookiesCookies._(
            names: _names?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'names';
        _names?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'LoginStepCookiesCookies', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
