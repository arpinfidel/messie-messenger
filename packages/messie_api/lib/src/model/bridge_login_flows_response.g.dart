// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bridge_login_flows_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BridgeLoginFlowsResponse extends BridgeLoginFlowsResponse {
  @override
  final BuiltList<BridgeLoginFlow>? flows;

  factory _$BridgeLoginFlowsResponse(
          [void Function(BridgeLoginFlowsResponseBuilder)? updates]) =>
      (BridgeLoginFlowsResponseBuilder()..update(updates))._build();

  _$BridgeLoginFlowsResponse._({this.flows}) : super._();
  @override
  BridgeLoginFlowsResponse rebuild(
          void Function(BridgeLoginFlowsResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BridgeLoginFlowsResponseBuilder toBuilder() =>
      BridgeLoginFlowsResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BridgeLoginFlowsResponse && flows == other.flows;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, flows.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BridgeLoginFlowsResponse')
          ..add('flows', flows))
        .toString();
  }
}

class BridgeLoginFlowsResponseBuilder
    implements
        Builder<BridgeLoginFlowsResponse, BridgeLoginFlowsResponseBuilder> {
  _$BridgeLoginFlowsResponse? _$v;

  ListBuilder<BridgeLoginFlow>? _flows;
  ListBuilder<BridgeLoginFlow> get flows =>
      _$this._flows ??= ListBuilder<BridgeLoginFlow>();
  set flows(ListBuilder<BridgeLoginFlow>? flows) => _$this._flows = flows;

  BridgeLoginFlowsResponseBuilder() {
    BridgeLoginFlowsResponse._defaults(this);
  }

  BridgeLoginFlowsResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _flows = $v.flows?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BridgeLoginFlowsResponse other) {
    _$v = other as _$BridgeLoginFlowsResponse;
  }

  @override
  void update(void Function(BridgeLoginFlowsResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BridgeLoginFlowsResponse build() => _build();

  _$BridgeLoginFlowsResponse _build() {
    _$BridgeLoginFlowsResponse _$result;
    try {
      _$result = _$v ??
          _$BridgeLoginFlowsResponse._(
            flows: _flows?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'flows';
        _flows?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'BridgeLoginFlowsResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
