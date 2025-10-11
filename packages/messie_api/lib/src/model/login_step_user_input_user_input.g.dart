// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'login_step_user_input_user_input.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LoginStepUserInputUserInput extends LoginStepUserInputUserInput {
  @override
  final BuiltList<LoginStepUserInputUserInputFieldsInner>? fields;

  factory _$LoginStepUserInputUserInput(
          [void Function(LoginStepUserInputUserInputBuilder)? updates]) =>
      (LoginStepUserInputUserInputBuilder()..update(updates))._build();

  _$LoginStepUserInputUserInput._({this.fields}) : super._();
  @override
  LoginStepUserInputUserInput rebuild(
          void Function(LoginStepUserInputUserInputBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LoginStepUserInputUserInputBuilder toBuilder() =>
      LoginStepUserInputUserInputBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LoginStepUserInputUserInput && fields == other.fields;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, fields.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LoginStepUserInputUserInput')
          ..add('fields', fields))
        .toString();
  }
}

class LoginStepUserInputUserInputBuilder
    implements
        Builder<LoginStepUserInputUserInput,
            LoginStepUserInputUserInputBuilder> {
  _$LoginStepUserInputUserInput? _$v;

  ListBuilder<LoginStepUserInputUserInputFieldsInner>? _fields;
  ListBuilder<LoginStepUserInputUserInputFieldsInner> get fields =>
      _$this._fields ??= ListBuilder<LoginStepUserInputUserInputFieldsInner>();
  set fields(ListBuilder<LoginStepUserInputUserInputFieldsInner>? fields) =>
      _$this._fields = fields;

  LoginStepUserInputUserInputBuilder() {
    LoginStepUserInputUserInput._defaults(this);
  }

  LoginStepUserInputUserInputBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _fields = $v.fields?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LoginStepUserInputUserInput other) {
    _$v = other as _$LoginStepUserInputUserInput;
  }

  @override
  void update(void Function(LoginStepUserInputUserInputBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LoginStepUserInputUserInput build() => _build();

  _$LoginStepUserInputUserInput _build() {
    _$LoginStepUserInputUserInput _$result;
    try {
      _$result = _$v ??
          _$LoginStepUserInputUserInput._(
            fields: _fields?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'fields';
        _fields?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'LoginStepUserInputUserInput', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
