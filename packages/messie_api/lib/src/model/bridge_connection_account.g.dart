// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bridge_connection_account.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BridgeConnectionAccount extends BridgeConnectionAccount {
  @override
  final String? externalId;
  @override
  final String? displayName;

  factory _$BridgeConnectionAccount(
          [void Function(BridgeConnectionAccountBuilder)? updates]) =>
      (BridgeConnectionAccountBuilder()..update(updates))._build();

  _$BridgeConnectionAccount._({this.externalId, this.displayName}) : super._();
  @override
  BridgeConnectionAccount rebuild(
          void Function(BridgeConnectionAccountBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BridgeConnectionAccountBuilder toBuilder() =>
      BridgeConnectionAccountBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BridgeConnectionAccount &&
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
    return (newBuiltValueToStringHelper(r'BridgeConnectionAccount')
          ..add('externalId', externalId)
          ..add('displayName', displayName))
        .toString();
  }
}

class BridgeConnectionAccountBuilder
    implements
        Builder<BridgeConnectionAccount, BridgeConnectionAccountBuilder> {
  _$BridgeConnectionAccount? _$v;

  String? _externalId;
  String? get externalId => _$this._externalId;
  set externalId(String? externalId) => _$this._externalId = externalId;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(String? displayName) => _$this._displayName = displayName;

  BridgeConnectionAccountBuilder() {
    BridgeConnectionAccount._defaults(this);
  }

  BridgeConnectionAccountBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _externalId = $v.externalId;
      _displayName = $v.displayName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BridgeConnectionAccount other) {
    _$v = other as _$BridgeConnectionAccount;
  }

  @override
  void update(void Function(BridgeConnectionAccountBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BridgeConnectionAccount build() => _build();

  _$BridgeConnectionAccount _build() {
    final _$result = _$v ??
        _$BridgeConnectionAccount._(
          externalId: externalId,
          displayName: displayName,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
