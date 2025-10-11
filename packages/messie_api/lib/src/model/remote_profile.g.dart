// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'remote_profile.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RemoteProfile extends RemoteProfile {
  @override
  final String? phone;
  @override
  final String? email;
  @override
  final String? username;
  @override
  final String? name;
  @override
  final String? avatar;

  factory _$RemoteProfile([void Function(RemoteProfileBuilder)? updates]) =>
      (RemoteProfileBuilder()..update(updates))._build();

  _$RemoteProfile._(
      {this.phone, this.email, this.username, this.name, this.avatar})
      : super._();
  @override
  RemoteProfile rebuild(void Function(RemoteProfileBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RemoteProfileBuilder toBuilder() => RemoteProfileBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RemoteProfile &&
        phone == other.phone &&
        email == other.email &&
        username == other.username &&
        name == other.name &&
        avatar == other.avatar;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, phone.hashCode);
    _$hash = $jc(_$hash, email.hashCode);
    _$hash = $jc(_$hash, username.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, avatar.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RemoteProfile')
          ..add('phone', phone)
          ..add('email', email)
          ..add('username', username)
          ..add('name', name)
          ..add('avatar', avatar))
        .toString();
  }
}

class RemoteProfileBuilder
    implements Builder<RemoteProfile, RemoteProfileBuilder> {
  _$RemoteProfile? _$v;

  String? _phone;
  String? get phone => _$this._phone;
  set phone(String? phone) => _$this._phone = phone;

  String? _email;
  String? get email => _$this._email;
  set email(String? email) => _$this._email = email;

  String? _username;
  String? get username => _$this._username;
  set username(String? username) => _$this._username = username;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _avatar;
  String? get avatar => _$this._avatar;
  set avatar(String? avatar) => _$this._avatar = avatar;

  RemoteProfileBuilder() {
    RemoteProfile._defaults(this);
  }

  RemoteProfileBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _phone = $v.phone;
      _email = $v.email;
      _username = $v.username;
      _name = $v.name;
      _avatar = $v.avatar;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RemoteProfile other) {
    _$v = other as _$RemoteProfile;
  }

  @override
  void update(void Function(RemoteProfileBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RemoteProfile build() => _build();

  _$RemoteProfile _build() {
    final _$result = _$v ??
        _$RemoteProfile._(
          phone: phone,
          email: email,
          username: username,
          name: name,
          avatar: avatar,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
