// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'login_step_complete_complete.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LoginStepCompleteComplete extends LoginStepCompleteComplete {
  @override
  final String? userLoginId;

  factory _$LoginStepCompleteComplete(
          [void Function(LoginStepCompleteCompleteBuilder)? updates]) =>
      (LoginStepCompleteCompleteBuilder()..update(updates))._build();

  _$LoginStepCompleteComplete._({this.userLoginId}) : super._();
  @override
  LoginStepCompleteComplete rebuild(
          void Function(LoginStepCompleteCompleteBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LoginStepCompleteCompleteBuilder toBuilder() =>
      LoginStepCompleteCompleteBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LoginStepCompleteComplete &&
        userLoginId == other.userLoginId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, userLoginId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LoginStepCompleteComplete')
          ..add('userLoginId', userLoginId))
        .toString();
  }
}

class LoginStepCompleteCompleteBuilder
    implements
        Builder<LoginStepCompleteComplete, LoginStepCompleteCompleteBuilder> {
  _$LoginStepCompleteComplete? _$v;

  String? _userLoginId;
  String? get userLoginId => _$this._userLoginId;
  set userLoginId(String? userLoginId) => _$this._userLoginId = userLoginId;

  LoginStepCompleteCompleteBuilder() {
    LoginStepCompleteComplete._defaults(this);
  }

  LoginStepCompleteCompleteBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _userLoginId = $v.userLoginId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LoginStepCompleteComplete other) {
    _$v = other as _$LoginStepCompleteComplete;
  }

  @override
  void update(void Function(LoginStepCompleteCompleteBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LoginStepCompleteComplete build() => _build();

  _$LoginStepCompleteComplete _build() {
    final _$result = _$v ??
        _$LoginStepCompleteComplete._(
          userLoginId: userLoginId,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
