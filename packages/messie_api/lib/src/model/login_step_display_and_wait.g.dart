// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'login_step_display_and_wait.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const LoginStepDisplayAndWaitTypeEnum
    _$loginStepDisplayAndWaitTypeEnum_displayAndWait =
    const LoginStepDisplayAndWaitTypeEnum._('displayAndWait');

LoginStepDisplayAndWaitTypeEnum _$loginStepDisplayAndWaitTypeEnumValueOf(
    String name) {
  switch (name) {
    case 'displayAndWait':
      return _$loginStepDisplayAndWaitTypeEnum_displayAndWait;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<LoginStepDisplayAndWaitTypeEnum>
    _$loginStepDisplayAndWaitTypeEnumValues = BuiltSet<
        LoginStepDisplayAndWaitTypeEnum>(const <LoginStepDisplayAndWaitTypeEnum>[
  _$loginStepDisplayAndWaitTypeEnum_displayAndWait,
]);

Serializer<LoginStepDisplayAndWaitTypeEnum>
    _$loginStepDisplayAndWaitTypeEnumSerializer =
    _$LoginStepDisplayAndWaitTypeEnumSerializer();

class _$LoginStepDisplayAndWaitTypeEnumSerializer
    implements PrimitiveSerializer<LoginStepDisplayAndWaitTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'displayAndWait': 'display_and_wait',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'display_and_wait': 'displayAndWait',
  };

  @override
  final Iterable<Type> types = const <Type>[LoginStepDisplayAndWaitTypeEnum];
  @override
  final String wireName = 'LoginStepDisplayAndWaitTypeEnum';

  @override
  Object serialize(
          Serializers serializers, LoginStepDisplayAndWaitTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  LoginStepDisplayAndWaitTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      LoginStepDisplayAndWaitTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$LoginStepDisplayAndWait extends LoginStepDisplayAndWait {
  @override
  final LoginStepDisplayAndWaitTypeEnum type;
  @override
  final LoginStepDisplayAndWaitDisplayAndWait displayAndWait;

  factory _$LoginStepDisplayAndWait(
          [void Function(LoginStepDisplayAndWaitBuilder)? updates]) =>
      (LoginStepDisplayAndWaitBuilder()..update(updates))._build();

  _$LoginStepDisplayAndWait._(
      {required this.type, required this.displayAndWait})
      : super._();
  @override
  LoginStepDisplayAndWait rebuild(
          void Function(LoginStepDisplayAndWaitBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LoginStepDisplayAndWaitBuilder toBuilder() =>
      LoginStepDisplayAndWaitBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LoginStepDisplayAndWait &&
        type == other.type &&
        displayAndWait == other.displayAndWait;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, displayAndWait.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LoginStepDisplayAndWait')
          ..add('type', type)
          ..add('displayAndWait', displayAndWait))
        .toString();
  }
}

class LoginStepDisplayAndWaitBuilder
    implements
        Builder<LoginStepDisplayAndWait, LoginStepDisplayAndWaitBuilder> {
  _$LoginStepDisplayAndWait? _$v;

  LoginStepDisplayAndWaitTypeEnum? _type;
  LoginStepDisplayAndWaitTypeEnum? get type => _$this._type;
  set type(LoginStepDisplayAndWaitTypeEnum? type) => _$this._type = type;

  LoginStepDisplayAndWaitDisplayAndWaitBuilder? _displayAndWait;
  LoginStepDisplayAndWaitDisplayAndWaitBuilder get displayAndWait =>
      _$this._displayAndWait ??= LoginStepDisplayAndWaitDisplayAndWaitBuilder();
  set displayAndWait(
          LoginStepDisplayAndWaitDisplayAndWaitBuilder? displayAndWait) =>
      _$this._displayAndWait = displayAndWait;

  LoginStepDisplayAndWaitBuilder() {
    LoginStepDisplayAndWait._defaults(this);
  }

  LoginStepDisplayAndWaitBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _type = $v.type;
      _displayAndWait = $v.displayAndWait.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LoginStepDisplayAndWait other) {
    _$v = other as _$LoginStepDisplayAndWait;
  }

  @override
  void update(void Function(LoginStepDisplayAndWaitBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LoginStepDisplayAndWait build() => _build();

  _$LoginStepDisplayAndWait _build() {
    _$LoginStepDisplayAndWait _$result;
    try {
      _$result = _$v ??
          _$LoginStepDisplayAndWait._(
            type: BuiltValueNullFieldError.checkNotNull(
                type, r'LoginStepDisplayAndWait', 'type'),
            displayAndWait: displayAndWait.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'displayAndWait';
        displayAndWait.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'LoginStepDisplayAndWait', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
