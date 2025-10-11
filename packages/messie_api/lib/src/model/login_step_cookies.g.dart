// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'login_step_cookies.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const LoginStepCookiesTypeEnum _$loginStepCookiesTypeEnum_cookies =
    const LoginStepCookiesTypeEnum._('cookies');

LoginStepCookiesTypeEnum _$loginStepCookiesTypeEnumValueOf(String name) {
  switch (name) {
    case 'cookies':
      return _$loginStepCookiesTypeEnum_cookies;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<LoginStepCookiesTypeEnum> _$loginStepCookiesTypeEnumValues =
    BuiltSet<LoginStepCookiesTypeEnum>(const <LoginStepCookiesTypeEnum>[
  _$loginStepCookiesTypeEnum_cookies,
]);

Serializer<LoginStepCookiesTypeEnum> _$loginStepCookiesTypeEnumSerializer =
    _$LoginStepCookiesTypeEnumSerializer();

class _$LoginStepCookiesTypeEnumSerializer
    implements PrimitiveSerializer<LoginStepCookiesTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'cookies': 'cookies',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'cookies': 'cookies',
  };

  @override
  final Iterable<Type> types = const <Type>[LoginStepCookiesTypeEnum];
  @override
  final String wireName = 'LoginStepCookiesTypeEnum';

  @override
  Object serialize(Serializers serializers, LoginStepCookiesTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  LoginStepCookiesTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      LoginStepCookiesTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$LoginStepCookies extends LoginStepCookies {
  @override
  final LoginStepCookiesTypeEnum type;
  @override
  final LoginStepCookiesCookies cookies;

  factory _$LoginStepCookies(
          [void Function(LoginStepCookiesBuilder)? updates]) =>
      (LoginStepCookiesBuilder()..update(updates))._build();

  _$LoginStepCookies._({required this.type, required this.cookies}) : super._();
  @override
  LoginStepCookies rebuild(void Function(LoginStepCookiesBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LoginStepCookiesBuilder toBuilder() =>
      LoginStepCookiesBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LoginStepCookies &&
        type == other.type &&
        cookies == other.cookies;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, cookies.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LoginStepCookies')
          ..add('type', type)
          ..add('cookies', cookies))
        .toString();
  }
}

class LoginStepCookiesBuilder
    implements Builder<LoginStepCookies, LoginStepCookiesBuilder> {
  _$LoginStepCookies? _$v;

  LoginStepCookiesTypeEnum? _type;
  LoginStepCookiesTypeEnum? get type => _$this._type;
  set type(LoginStepCookiesTypeEnum? type) => _$this._type = type;

  LoginStepCookiesCookiesBuilder? _cookies;
  LoginStepCookiesCookiesBuilder get cookies =>
      _$this._cookies ??= LoginStepCookiesCookiesBuilder();
  set cookies(LoginStepCookiesCookiesBuilder? cookies) =>
      _$this._cookies = cookies;

  LoginStepCookiesBuilder() {
    LoginStepCookies._defaults(this);
  }

  LoginStepCookiesBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _type = $v.type;
      _cookies = $v.cookies.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LoginStepCookies other) {
    _$v = other as _$LoginStepCookies;
  }

  @override
  void update(void Function(LoginStepCookiesBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LoginStepCookies build() => _build();

  _$LoginStepCookies _build() {
    _$LoginStepCookies _$result;
    try {
      _$result = _$v ??
          _$LoginStepCookies._(
            type: BuiltValueNullFieldError.checkNotNull(
                type, r'LoginStepCookies', 'type'),
            cookies: cookies.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'cookies';
        cookies.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'LoginStepCookies', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
