// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bridge_connection.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const BridgeConnectionStatusEnum _$bridgeConnectionStatusEnum_notConnected =
    const BridgeConnectionStatusEnum._('notConnected');
const BridgeConnectionStatusEnum _$bridgeConnectionStatusEnum_connecting =
    const BridgeConnectionStatusEnum._('connecting');
const BridgeConnectionStatusEnum _$bridgeConnectionStatusEnum_connected =
    const BridgeConnectionStatusEnum._('connected');

BridgeConnectionStatusEnum _$bridgeConnectionStatusEnumValueOf(String name) {
  switch (name) {
    case 'notConnected':
      return _$bridgeConnectionStatusEnum_notConnected;
    case 'connecting':
      return _$bridgeConnectionStatusEnum_connecting;
    case 'connected':
      return _$bridgeConnectionStatusEnum_connected;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<BridgeConnectionStatusEnum> _$bridgeConnectionStatusEnumValues =
    BuiltSet<BridgeConnectionStatusEnum>(const <BridgeConnectionStatusEnum>[
  _$bridgeConnectionStatusEnum_notConnected,
  _$bridgeConnectionStatusEnum_connecting,
  _$bridgeConnectionStatusEnum_connected,
]);

Serializer<BridgeConnectionStatusEnum> _$bridgeConnectionStatusEnumSerializer =
    _$BridgeConnectionStatusEnumSerializer();

class _$BridgeConnectionStatusEnumSerializer
    implements PrimitiveSerializer<BridgeConnectionStatusEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'notConnected': 'not_connected',
    'connecting': 'connecting',
    'connected': 'connected',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'not_connected': 'notConnected',
    'connecting': 'connecting',
    'connected': 'connected',
  };

  @override
  final Iterable<Type> types = const <Type>[BridgeConnectionStatusEnum];
  @override
  final String wireName = 'BridgeConnectionStatusEnum';

  @override
  Object serialize(Serializers serializers, BridgeConnectionStatusEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  BridgeConnectionStatusEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      BridgeConnectionStatusEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$BridgeConnection extends BridgeConnection {
  @override
  final String provider;
  @override
  final BridgeConnectionStatusEnum status;
  @override
  final BridgeAccount? account;
  @override
  final BuiltMap<String, JsonObject?>? limits;

  factory _$BridgeConnection(
          [void Function(BridgeConnectionBuilder)? updates]) =>
      (BridgeConnectionBuilder()..update(updates))._build();

  _$BridgeConnection._(
      {required this.provider, required this.status, this.account, this.limits})
      : super._();
  @override
  BridgeConnection rebuild(void Function(BridgeConnectionBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BridgeConnectionBuilder toBuilder() =>
      BridgeConnectionBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BridgeConnection &&
        provider == other.provider &&
        status == other.status &&
        account == other.account &&
        limits == other.limits;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, account.hashCode);
    _$hash = $jc(_$hash, limits.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BridgeConnection')
          ..add('provider', provider)
          ..add('status', status)
          ..add('account', account)
          ..add('limits', limits))
        .toString();
  }
}

class BridgeConnectionBuilder
    implements Builder<BridgeConnection, BridgeConnectionBuilder> {
  _$BridgeConnection? _$v;

  String? _provider;
  String? get provider => _$this._provider;
  set provider(String? provider) => _$this._provider = provider;

  BridgeConnectionStatusEnum? _status;
  BridgeConnectionStatusEnum? get status => _$this._status;
  set status(BridgeConnectionStatusEnum? status) => _$this._status = status;

  BridgeAccountBuilder? _account;
  BridgeAccountBuilder get account =>
      _$this._account ??= BridgeAccountBuilder();
  set account(BridgeAccountBuilder? account) => _$this._account = account;

  MapBuilder<String, JsonObject?>? _limits;
  MapBuilder<String, JsonObject?> get limits =>
      _$this._limits ??= MapBuilder<String, JsonObject?>();
  set limits(MapBuilder<String, JsonObject?>? limits) =>
      _$this._limits = limits;

  BridgeConnectionBuilder() {
    BridgeConnection._defaults(this);
  }

  BridgeConnectionBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _provider = $v.provider;
      _status = $v.status;
      _account = $v.account?.toBuilder();
      _limits = $v.limits?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BridgeConnection other) {
    _$v = other as _$BridgeConnection;
  }

  @override
  void update(void Function(BridgeConnectionBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BridgeConnection build() => _build();

  _$BridgeConnection _build() {
    _$BridgeConnection _$result;
    try {
      _$result = _$v ??
          _$BridgeConnection._(
            provider: BuiltValueNullFieldError.checkNotNull(
                provider, r'BridgeConnection', 'provider'),
            status: BuiltValueNullFieldError.checkNotNull(
                status, r'BridgeConnection', 'status'),
            account: _account?.build(),
            limits: _limits?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'account';
        _account?.build();
        _$failedField = 'limits';
        _limits?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'BridgeConnection', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
