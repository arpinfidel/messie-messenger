// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bridge_state.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const BridgeStateStateEventEnum _$bridgeStateStateEventEnum_CONNECTING =
    const BridgeStateStateEventEnum._('CONNECTING');
const BridgeStateStateEventEnum _$bridgeStateStateEventEnum_CONNECTED =
    const BridgeStateStateEventEnum._('CONNECTED');
const BridgeStateStateEventEnum
    _$bridgeStateStateEventEnum_TRANSIENT_DISCONNECT =
    const BridgeStateStateEventEnum._('TRANSIENT_DISCONNECT');
const BridgeStateStateEventEnum _$bridgeStateStateEventEnum_BAD_CREDENTIALS =
    const BridgeStateStateEventEnum._('BAD_CREDENTIALS');
const BridgeStateStateEventEnum _$bridgeStateStateEventEnum_UNKNOWN_ERROR =
    const BridgeStateStateEventEnum._('UNKNOWN_ERROR');

BridgeStateStateEventEnum _$bridgeStateStateEventEnumValueOf(String name) {
  switch (name) {
    case 'CONNECTING':
      return _$bridgeStateStateEventEnum_CONNECTING;
    case 'CONNECTED':
      return _$bridgeStateStateEventEnum_CONNECTED;
    case 'TRANSIENT_DISCONNECT':
      return _$bridgeStateStateEventEnum_TRANSIENT_DISCONNECT;
    case 'BAD_CREDENTIALS':
      return _$bridgeStateStateEventEnum_BAD_CREDENTIALS;
    case 'UNKNOWN_ERROR':
      return _$bridgeStateStateEventEnum_UNKNOWN_ERROR;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<BridgeStateStateEventEnum> _$bridgeStateStateEventEnumValues =
    BuiltSet<BridgeStateStateEventEnum>(const <BridgeStateStateEventEnum>[
  _$bridgeStateStateEventEnum_CONNECTING,
  _$bridgeStateStateEventEnum_CONNECTED,
  _$bridgeStateStateEventEnum_TRANSIENT_DISCONNECT,
  _$bridgeStateStateEventEnum_BAD_CREDENTIALS,
  _$bridgeStateStateEventEnum_UNKNOWN_ERROR,
]);

Serializer<BridgeStateStateEventEnum> _$bridgeStateStateEventEnumSerializer =
    _$BridgeStateStateEventEnumSerializer();

class _$BridgeStateStateEventEnumSerializer
    implements PrimitiveSerializer<BridgeStateStateEventEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'CONNECTING': 'CONNECTING',
    'CONNECTED': 'CONNECTED',
    'TRANSIENT_DISCONNECT': 'TRANSIENT_DISCONNECT',
    'BAD_CREDENTIALS': 'BAD_CREDENTIALS',
    'UNKNOWN_ERROR': 'UNKNOWN_ERROR',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'CONNECTING': 'CONNECTING',
    'CONNECTED': 'CONNECTED',
    'TRANSIENT_DISCONNECT': 'TRANSIENT_DISCONNECT',
    'BAD_CREDENTIALS': 'BAD_CREDENTIALS',
    'UNKNOWN_ERROR': 'UNKNOWN_ERROR',
  };

  @override
  final Iterable<Type> types = const <Type>[BridgeStateStateEventEnum];
  @override
  final String wireName = 'BridgeStateStateEventEnum';

  @override
  Object serialize(Serializers serializers, BridgeStateStateEventEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  BridgeStateStateEventEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      BridgeStateStateEventEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$BridgeState extends BridgeState {
  @override
  final BridgeStateStateEventEnum stateEvent;
  @override
  final double timestamp;
  @override
  final String? error;
  @override
  final String? message;
  @override
  final String? reason;
  @override
  final BuiltMap<String, JsonObject?>? info;

  factory _$BridgeState([void Function(BridgeStateBuilder)? updates]) =>
      (BridgeStateBuilder()..update(updates))._build();

  _$BridgeState._(
      {required this.stateEvent,
      required this.timestamp,
      this.error,
      this.message,
      this.reason,
      this.info})
      : super._();
  @override
  BridgeState rebuild(void Function(BridgeStateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BridgeStateBuilder toBuilder() => BridgeStateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BridgeState &&
        stateEvent == other.stateEvent &&
        timestamp == other.timestamp &&
        error == other.error &&
        message == other.message &&
        reason == other.reason &&
        info == other.info;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, stateEvent.hashCode);
    _$hash = $jc(_$hash, timestamp.hashCode);
    _$hash = $jc(_$hash, error.hashCode);
    _$hash = $jc(_$hash, message.hashCode);
    _$hash = $jc(_$hash, reason.hashCode);
    _$hash = $jc(_$hash, info.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BridgeState')
          ..add('stateEvent', stateEvent)
          ..add('timestamp', timestamp)
          ..add('error', error)
          ..add('message', message)
          ..add('reason', reason)
          ..add('info', info))
        .toString();
  }
}

class BridgeStateBuilder implements Builder<BridgeState, BridgeStateBuilder> {
  _$BridgeState? _$v;

  BridgeStateStateEventEnum? _stateEvent;
  BridgeStateStateEventEnum? get stateEvent => _$this._stateEvent;
  set stateEvent(BridgeStateStateEventEnum? stateEvent) =>
      _$this._stateEvent = stateEvent;

  double? _timestamp;
  double? get timestamp => _$this._timestamp;
  set timestamp(double? timestamp) => _$this._timestamp = timestamp;

  String? _error;
  String? get error => _$this._error;
  set error(String? error) => _$this._error = error;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  String? _reason;
  String? get reason => _$this._reason;
  set reason(String? reason) => _$this._reason = reason;

  MapBuilder<String, JsonObject?>? _info;
  MapBuilder<String, JsonObject?> get info =>
      _$this._info ??= MapBuilder<String, JsonObject?>();
  set info(MapBuilder<String, JsonObject?>? info) => _$this._info = info;

  BridgeStateBuilder() {
    BridgeState._defaults(this);
  }

  BridgeStateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _stateEvent = $v.stateEvent;
      _timestamp = $v.timestamp;
      _error = $v.error;
      _message = $v.message;
      _reason = $v.reason;
      _info = $v.info?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BridgeState other) {
    _$v = other as _$BridgeState;
  }

  @override
  void update(void Function(BridgeStateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BridgeState build() => _build();

  _$BridgeState _build() {
    _$BridgeState _$result;
    try {
      _$result = _$v ??
          _$BridgeState._(
            stateEvent: BuiltValueNullFieldError.checkNotNull(
                stateEvent, r'BridgeState', 'stateEvent'),
            timestamp: BuiltValueNullFieldError.checkNotNull(
                timestamp, r'BridgeState', 'timestamp'),
            error: error,
            message: message,
            reason: reason,
            info: _info?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'info';
        _info?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'BridgeState', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
