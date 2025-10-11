// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'login_step_user_input_user_input_fields_inner.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LoginStepUserInputUserInputFieldsInner
    extends LoginStepUserInputUserInputFieldsInner {
  @override
  final String? id;
  @override
  final String? label;
  @override
  final String? kind;
  @override
  final bool? secret;

  factory _$LoginStepUserInputUserInputFieldsInner(
          [void Function(LoginStepUserInputUserInputFieldsInnerBuilder)?
              updates]) =>
      (LoginStepUserInputUserInputFieldsInnerBuilder()..update(updates))
          ._build();

  _$LoginStepUserInputUserInputFieldsInner._(
      {this.id, this.label, this.kind, this.secret})
      : super._();
  @override
  LoginStepUserInputUserInputFieldsInner rebuild(
          void Function(LoginStepUserInputUserInputFieldsInnerBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LoginStepUserInputUserInputFieldsInnerBuilder toBuilder() =>
      LoginStepUserInputUserInputFieldsInnerBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LoginStepUserInputUserInputFieldsInner &&
        id == other.id &&
        label == other.label &&
        kind == other.kind &&
        secret == other.secret;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, label.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, secret.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
            r'LoginStepUserInputUserInputFieldsInner')
          ..add('id', id)
          ..add('label', label)
          ..add('kind', kind)
          ..add('secret', secret))
        .toString();
  }
}

class LoginStepUserInputUserInputFieldsInnerBuilder
    implements
        Builder<LoginStepUserInputUserInputFieldsInner,
            LoginStepUserInputUserInputFieldsInnerBuilder> {
  _$LoginStepUserInputUserInputFieldsInner? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _label;
  String? get label => _$this._label;
  set label(String? label) => _$this._label = label;

  String? _kind;
  String? get kind => _$this._kind;
  set kind(String? kind) => _$this._kind = kind;

  bool? _secret;
  bool? get secret => _$this._secret;
  set secret(bool? secret) => _$this._secret = secret;

  LoginStepUserInputUserInputFieldsInnerBuilder() {
    LoginStepUserInputUserInputFieldsInner._defaults(this);
  }

  LoginStepUserInputUserInputFieldsInnerBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _label = $v.label;
      _kind = $v.kind;
      _secret = $v.secret;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LoginStepUserInputUserInputFieldsInner other) {
    _$v = other as _$LoginStepUserInputUserInputFieldsInner;
  }

  @override
  void update(
      void Function(LoginStepUserInputUserInputFieldsInnerBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LoginStepUserInputUserInputFieldsInner build() => _build();

  _$LoginStepUserInputUserInputFieldsInner _build() {
    final _$result = _$v ??
        _$LoginStepUserInputUserInputFieldsInner._(
          id: id,
          label: label,
          kind: kind,
          secret: secret,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
