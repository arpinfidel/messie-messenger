// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bridge_name.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BridgeName extends BridgeName {
  @override
  final String displayname;
  @override
  final String networkUrl;
  @override
  final String networkIcon;
  @override
  final String networkId;
  @override
  final String? beeperBridgeType;

  factory _$BridgeName([void Function(BridgeNameBuilder)? updates]) =>
      (BridgeNameBuilder()..update(updates))._build();

  _$BridgeName._(
      {required this.displayname,
      required this.networkUrl,
      required this.networkIcon,
      required this.networkId,
      this.beeperBridgeType})
      : super._();
  @override
  BridgeName rebuild(void Function(BridgeNameBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BridgeNameBuilder toBuilder() => BridgeNameBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BridgeName &&
        displayname == other.displayname &&
        networkUrl == other.networkUrl &&
        networkIcon == other.networkIcon &&
        networkId == other.networkId &&
        beeperBridgeType == other.beeperBridgeType;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, displayname.hashCode);
    _$hash = $jc(_$hash, networkUrl.hashCode);
    _$hash = $jc(_$hash, networkIcon.hashCode);
    _$hash = $jc(_$hash, networkId.hashCode);
    _$hash = $jc(_$hash, beeperBridgeType.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BridgeName')
          ..add('displayname', displayname)
          ..add('networkUrl', networkUrl)
          ..add('networkIcon', networkIcon)
          ..add('networkId', networkId)
          ..add('beeperBridgeType', beeperBridgeType))
        .toString();
  }
}

class BridgeNameBuilder implements Builder<BridgeName, BridgeNameBuilder> {
  _$BridgeName? _$v;

  String? _displayname;
  String? get displayname => _$this._displayname;
  set displayname(String? displayname) => _$this._displayname = displayname;

  String? _networkUrl;
  String? get networkUrl => _$this._networkUrl;
  set networkUrl(String? networkUrl) => _$this._networkUrl = networkUrl;

  String? _networkIcon;
  String? get networkIcon => _$this._networkIcon;
  set networkIcon(String? networkIcon) => _$this._networkIcon = networkIcon;

  String? _networkId;
  String? get networkId => _$this._networkId;
  set networkId(String? networkId) => _$this._networkId = networkId;

  String? _beeperBridgeType;
  String? get beeperBridgeType => _$this._beeperBridgeType;
  set beeperBridgeType(String? beeperBridgeType) =>
      _$this._beeperBridgeType = beeperBridgeType;

  BridgeNameBuilder() {
    BridgeName._defaults(this);
  }

  BridgeNameBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _displayname = $v.displayname;
      _networkUrl = $v.networkUrl;
      _networkIcon = $v.networkIcon;
      _networkId = $v.networkId;
      _beeperBridgeType = $v.beeperBridgeType;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BridgeName other) {
    _$v = other as _$BridgeName;
  }

  @override
  void update(void Function(BridgeNameBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BridgeName build() => _build();

  _$BridgeName _build() {
    final _$result = _$v ??
        _$BridgeName._(
          displayname: BuiltValueNullFieldError.checkNotNull(
              displayname, r'BridgeName', 'displayname'),
          networkUrl: BuiltValueNullFieldError.checkNotNull(
              networkUrl, r'BridgeName', 'networkUrl'),
          networkIcon: BuiltValueNullFieldError.checkNotNull(
              networkIcon, r'BridgeName', 'networkIcon'),
          networkId: BuiltValueNullFieldError.checkNotNull(
              networkId, r'BridgeName', 'networkId'),
          beeperBridgeType: beeperBridgeType,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
