// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'login_step_display_and_wait_display_and_wait.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LoginStepDisplayAndWaitDisplayAndWait
    extends LoginStepDisplayAndWaitDisplayAndWait {
  @override
  final String? message;
  @override
  final String? data;
  @override
  final String? imageUrl;

  factory _$LoginStepDisplayAndWaitDisplayAndWait(
          [void Function(LoginStepDisplayAndWaitDisplayAndWaitBuilder)?
              updates]) =>
      (LoginStepDisplayAndWaitDisplayAndWaitBuilder()..update(updates))
          ._build();

  _$LoginStepDisplayAndWaitDisplayAndWait._(
      {this.message, this.data, this.imageUrl})
      : super._();
  @override
  LoginStepDisplayAndWaitDisplayAndWait rebuild(
          void Function(LoginStepDisplayAndWaitDisplayAndWaitBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LoginStepDisplayAndWaitDisplayAndWaitBuilder toBuilder() =>
      LoginStepDisplayAndWaitDisplayAndWaitBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LoginStepDisplayAndWaitDisplayAndWait &&
        message == other.message &&
        data == other.data &&
        imageUrl == other.imageUrl;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, message.hashCode);
    _$hash = $jc(_$hash, data.hashCode);
    _$hash = $jc(_$hash, imageUrl.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
            r'LoginStepDisplayAndWaitDisplayAndWait')
          ..add('message', message)
          ..add('data', data)
          ..add('imageUrl', imageUrl))
        .toString();
  }
}

class LoginStepDisplayAndWaitDisplayAndWaitBuilder
    implements
        Builder<LoginStepDisplayAndWaitDisplayAndWait,
            LoginStepDisplayAndWaitDisplayAndWaitBuilder> {
  _$LoginStepDisplayAndWaitDisplayAndWait? _$v;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  String? _data;
  String? get data => _$this._data;
  set data(String? data) => _$this._data = data;

  String? _imageUrl;
  String? get imageUrl => _$this._imageUrl;
  set imageUrl(String? imageUrl) => _$this._imageUrl = imageUrl;

  LoginStepDisplayAndWaitDisplayAndWaitBuilder() {
    LoginStepDisplayAndWaitDisplayAndWait._defaults(this);
  }

  LoginStepDisplayAndWaitDisplayAndWaitBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _message = $v.message;
      _data = $v.data;
      _imageUrl = $v.imageUrl;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LoginStepDisplayAndWaitDisplayAndWait other) {
    _$v = other as _$LoginStepDisplayAndWaitDisplayAndWait;
  }

  @override
  void update(
      void Function(LoginStepDisplayAndWaitDisplayAndWaitBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LoginStepDisplayAndWaitDisplayAndWait build() => _build();

  _$LoginStepDisplayAndWaitDisplayAndWait _build() {
    final _$result = _$v ??
        _$LoginStepDisplayAndWaitDisplayAndWait._(
          message: message,
          data: data,
          imageUrl: imageUrl,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
