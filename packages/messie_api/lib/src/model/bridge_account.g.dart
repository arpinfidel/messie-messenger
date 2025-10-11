// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bridge_account.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BridgeAccount extends BridgeAccount {
  @override
  final String? externalId;
  @override
  final String? displayName;

  factory _$BridgeAccount([void Function(BridgeAccountBuilder)? updates]) =>
      (BridgeAccountBuilder()..update(updates))._build();

  _$BridgeAccount._({this.externalId, this.displayName}) : super._();
  @override
  BridgeAccount rebuild(void Function(BridgeAccountBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BridgeAccountBuilder toBuilder() => BridgeAccountBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BridgeAccount &&
        externalId == other.externalId &&
        displayName == other.displayName;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, externalId.hashCode);
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BridgeAccount')
          ..add('externalId', externalId)
          ..add('displayName', displayName))
        .toString();
  }
}

class BridgeAccountBuilder
    implements Builder<BridgeAccount, BridgeAccountBuilder> {
  _$BridgeAccount? _$v;

  String? _externalId;
  String? get externalId => _$this._externalId;
  set externalId(String? externalId) => _$this._externalId = externalId;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(String? displayName) => _$this._displayName = displayName;

  BridgeAccountBuilder() {
    BridgeAccount._defaults(this);
  }

  BridgeAccountBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _externalId = $v.externalId;
      _displayName = $v.displayName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BridgeAccount other) {
    _$v = other as _$BridgeAccount;
  }

  @override
  void update(void Function(BridgeAccountBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BridgeAccount build() => _build();

  _$BridgeAccount _build() {
    final _$result = _$v ??
        _$BridgeAccount._(
          externalId: externalId,
          displayName: displayName,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
