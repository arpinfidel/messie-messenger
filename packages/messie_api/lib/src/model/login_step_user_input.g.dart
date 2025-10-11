// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'login_step_user_input.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const LoginStepUserInputTypeEnum _$loginStepUserInputTypeEnum_userInput =
    const LoginStepUserInputTypeEnum._('userInput');

LoginStepUserInputTypeEnum _$loginStepUserInputTypeEnumValueOf(String name) {
  switch (name) {
    case 'userInput':
      return _$loginStepUserInputTypeEnum_userInput;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<LoginStepUserInputTypeEnum> _$loginStepUserInputTypeEnumValues =
    BuiltSet<LoginStepUserInputTypeEnum>(const <LoginStepUserInputTypeEnum>[
  _$loginStepUserInputTypeEnum_userInput,
]);

Serializer<LoginStepUserInputTypeEnum> _$loginStepUserInputTypeEnumSerializer =
    _$LoginStepUserInputTypeEnumSerializer();

class _$LoginStepUserInputTypeEnumSerializer
    implements PrimitiveSerializer<LoginStepUserInputTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'userInput': 'user_input',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'user_input': 'userInput',
  };

  @override
  final Iterable<Type> types = const <Type>[LoginStepUserInputTypeEnum];
  @override
  final String wireName = 'LoginStepUserInputTypeEnum';

  @override
  Object serialize(Serializers serializers, LoginStepUserInputTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  LoginStepUserInputTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      LoginStepUserInputTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$LoginStepUserInput extends LoginStepUserInput {
  @override
  final LoginStepUserInputTypeEnum type;
  @override
  final LoginStepUserInputUserInput userInput;

  factory _$LoginStepUserInput(
          [void Function(LoginStepUserInputBuilder)? updates]) =>
      (LoginStepUserInputBuilder()..update(updates))._build();

  _$LoginStepUserInput._({required this.type, required this.userInput})
      : super._();
  @override
  LoginStepUserInput rebuild(
          void Function(LoginStepUserInputBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LoginStepUserInputBuilder toBuilder() =>
      LoginStepUserInputBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LoginStepUserInput &&
        type == other.type &&
        userInput == other.userInput;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, userInput.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LoginStepUserInput')
          ..add('type', type)
          ..add('userInput', userInput))
        .toString();
  }
}

class LoginStepUserInputBuilder
    implements Builder<LoginStepUserInput, LoginStepUserInputBuilder> {
  _$LoginStepUserInput? _$v;

  LoginStepUserInputTypeEnum? _type;
  LoginStepUserInputTypeEnum? get type => _$this._type;
  set type(LoginStepUserInputTypeEnum? type) => _$this._type = type;

  LoginStepUserInputUserInputBuilder? _userInput;
  LoginStepUserInputUserInputBuilder get userInput =>
      _$this._userInput ??= LoginStepUserInputUserInputBuilder();
  set userInput(LoginStepUserInputUserInputBuilder? userInput) =>
      _$this._userInput = userInput;

  LoginStepUserInputBuilder() {
    LoginStepUserInput._defaults(this);
  }

  LoginStepUserInputBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _type = $v.type;
      _userInput = $v.userInput.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LoginStepUserInput other) {
    _$v = other as _$LoginStepUserInput;
  }

  @override
  void update(void Function(LoginStepUserInputBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LoginStepUserInput build() => _build();

  _$LoginStepUserInput _build() {
    _$LoginStepUserInput _$result;
    try {
      _$result = _$v ??
          _$LoginStepUserInput._(
            type: BuiltValueNullFieldError.checkNotNull(
                type, r'LoginStepUserInput', 'type'),
            userInput: userInput.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'userInput';
        userInput.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'LoginStepUserInput', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
