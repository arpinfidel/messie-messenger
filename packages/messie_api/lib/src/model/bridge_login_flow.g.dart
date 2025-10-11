// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bridge_login_flow.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BridgeLoginFlow extends BridgeLoginFlow {
  @override
  final String id;
  @override
  final String name;
  @override
  final String description;

  factory _$BridgeLoginFlow([void Function(BridgeLoginFlowBuilder)? updates]) =>
      (BridgeLoginFlowBuilder()..update(updates))._build();

  _$BridgeLoginFlow._(
      {required this.id, required this.name, required this.description})
      : super._();
  @override
  BridgeLoginFlow rebuild(void Function(BridgeLoginFlowBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BridgeLoginFlowBuilder toBuilder() => BridgeLoginFlowBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BridgeLoginFlow &&
        id == other.id &&
        name == other.name &&
        description == other.description;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BridgeLoginFlow')
          ..add('id', id)
          ..add('name', name)
          ..add('description', description))
        .toString();
  }
}

class BridgeLoginFlowBuilder
    implements Builder<BridgeLoginFlow, BridgeLoginFlowBuilder> {
  _$BridgeLoginFlow? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _description;
  String? get description => _$this._description;
  set description(String? description) => _$this._description = description;

  BridgeLoginFlowBuilder() {
    BridgeLoginFlow._defaults(this);
  }

  BridgeLoginFlowBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _name = $v.name;
      _description = $v.description;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BridgeLoginFlow other) {
    _$v = other as _$BridgeLoginFlow;
  }

  @override
  void update(void Function(BridgeLoginFlowBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BridgeLoginFlow build() => _build();

  _$BridgeLoginFlow _build() {
    final _$result = _$v ??
        _$BridgeLoginFlow._(
          id: BuiltValueNullFieldError.checkNotNull(
              id, r'BridgeLoginFlow', 'id'),
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'BridgeLoginFlow', 'name'),
          description: BuiltValueNullFieldError.checkNotNull(
              description, r'BridgeLoginFlow', 'description'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
