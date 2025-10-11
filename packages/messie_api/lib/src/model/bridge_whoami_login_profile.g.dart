// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bridge_whoami_login_profile.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BridgeWhoamiLoginProfile extends BridgeWhoamiLoginProfile {
  @override
  final String? displayName;
  @override
  final String? externalId;

  factory _$BridgeWhoamiLoginProfile(
          [void Function(BridgeWhoamiLoginProfileBuilder)? updates]) =>
      (BridgeWhoamiLoginProfileBuilder()..update(updates))._build();

  _$BridgeWhoamiLoginProfile._({this.displayName, this.externalId}) : super._();
  @override
  BridgeWhoamiLoginProfile rebuild(
          void Function(BridgeWhoamiLoginProfileBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BridgeWhoamiLoginProfileBuilder toBuilder() =>
      BridgeWhoamiLoginProfileBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BridgeWhoamiLoginProfile &&
        displayName == other.displayName &&
        externalId == other.externalId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jc(_$hash, externalId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BridgeWhoamiLoginProfile')
          ..add('displayName', displayName)
          ..add('externalId', externalId))
        .toString();
  }
}

class BridgeWhoamiLoginProfileBuilder
    implements
        Builder<BridgeWhoamiLoginProfile, BridgeWhoamiLoginProfileBuilder> {
  _$BridgeWhoamiLoginProfile? _$v;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(String? displayName) => _$this._displayName = displayName;

  String? _externalId;
  String? get externalId => _$this._externalId;
  set externalId(String? externalId) => _$this._externalId = externalId;

  BridgeWhoamiLoginProfileBuilder() {
    BridgeWhoamiLoginProfile._defaults(this);
  }

  BridgeWhoamiLoginProfileBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _displayName = $v.displayName;
      _externalId = $v.externalId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BridgeWhoamiLoginProfile other) {
    _$v = other as _$BridgeWhoamiLoginProfile;
  }

  @override
  void update(void Function(BridgeWhoamiLoginProfileBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BridgeWhoamiLoginProfile build() => _build();

  _$BridgeWhoamiLoginProfile _build() {
    final _$result = _$v ??
        _$BridgeWhoamiLoginProfile._(
          displayName: displayName,
          externalId: externalId,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
