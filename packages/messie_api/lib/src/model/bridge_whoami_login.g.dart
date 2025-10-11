// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bridge_whoami_login.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BridgeWhoamiLogin extends BridgeWhoamiLogin {
  @override
  final String id;
  @override
  final String name;
  @override
  final String? state;
  @override
  final BridgeWhoamiLoginProfile? profile;

  factory _$BridgeWhoamiLogin(
          [void Function(BridgeWhoamiLoginBuilder)? updates]) =>
      (BridgeWhoamiLoginBuilder()..update(updates))._build();

  _$BridgeWhoamiLogin._(
      {required this.id, required this.name, this.state, this.profile})
      : super._();
  @override
  BridgeWhoamiLogin rebuild(void Function(BridgeWhoamiLoginBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BridgeWhoamiLoginBuilder toBuilder() =>
      BridgeWhoamiLoginBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BridgeWhoamiLogin &&
        id == other.id &&
        name == other.name &&
        state == other.state &&
        profile == other.profile;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, state.hashCode);
    _$hash = $jc(_$hash, profile.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BridgeWhoamiLogin')
          ..add('id', id)
          ..add('name', name)
          ..add('state', state)
          ..add('profile', profile))
        .toString();
  }
}

class BridgeWhoamiLoginBuilder
    implements Builder<BridgeWhoamiLogin, BridgeWhoamiLoginBuilder> {
  _$BridgeWhoamiLogin? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _state;
  String? get state => _$this._state;
  set state(String? state) => _$this._state = state;

  BridgeWhoamiLoginProfileBuilder? _profile;
  BridgeWhoamiLoginProfileBuilder get profile =>
      _$this._profile ??= BridgeWhoamiLoginProfileBuilder();
  set profile(BridgeWhoamiLoginProfileBuilder? profile) =>
      _$this._profile = profile;

  BridgeWhoamiLoginBuilder() {
    BridgeWhoamiLogin._defaults(this);
  }

  BridgeWhoamiLoginBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _name = $v.name;
      _state = $v.state;
      _profile = $v.profile?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BridgeWhoamiLogin other) {
    _$v = other as _$BridgeWhoamiLogin;
  }

  @override
  void update(void Function(BridgeWhoamiLoginBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BridgeWhoamiLogin build() => _build();

  _$BridgeWhoamiLogin _build() {
    _$BridgeWhoamiLogin _$result;
    try {
      _$result = _$v ??
          _$BridgeWhoamiLogin._(
            id: BuiltValueNullFieldError.checkNotNull(
                id, r'BridgeWhoamiLogin', 'id'),
            name: BuiltValueNullFieldError.checkNotNull(
                name, r'BridgeWhoamiLogin', 'name'),
            state: state,
            profile: _profile?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'profile';
        _profile?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'BridgeWhoamiLogin', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
