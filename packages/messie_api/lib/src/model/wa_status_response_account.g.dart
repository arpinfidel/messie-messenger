// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'wa_status_response_account.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$WAStatusResponseAccount extends WAStatusResponseAccount {
  @override
  final String? externalId;
  @override
  final String? displayName;

  factory _$WAStatusResponseAccount(
          [void Function(WAStatusResponseAccountBuilder)? updates]) =>
      (WAStatusResponseAccountBuilder()..update(updates))._build();

  _$WAStatusResponseAccount._({this.externalId, this.displayName}) : super._();
  @override
  WAStatusResponseAccount rebuild(
          void Function(WAStatusResponseAccountBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WAStatusResponseAccountBuilder toBuilder() =>
      WAStatusResponseAccountBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WAStatusResponseAccount &&
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
    return (newBuiltValueToStringHelper(r'WAStatusResponseAccount')
          ..add('externalId', externalId)
          ..add('displayName', displayName))
        .toString();
  }
}

class WAStatusResponseAccountBuilder
    implements
        Builder<WAStatusResponseAccount, WAStatusResponseAccountBuilder> {
  _$WAStatusResponseAccount? _$v;

  String? _externalId;
  String? get externalId => _$this._externalId;
  set externalId(String? externalId) => _$this._externalId = externalId;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(String? displayName) => _$this._displayName = displayName;

  WAStatusResponseAccountBuilder() {
    WAStatusResponseAccount._defaults(this);
  }

  WAStatusResponseAccountBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _externalId = $v.externalId;
      _displayName = $v.displayName;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WAStatusResponseAccount other) {
    _$v = other as _$WAStatusResponseAccount;
  }

  @override
  void update(void Function(WAStatusResponseAccountBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WAStatusResponseAccount build() => _build();

  _$WAStatusResponseAccount _build() {
    final _$result = _$v ??
        _$WAStatusResponseAccount._(
          externalId: externalId,
          displayName: displayName,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
