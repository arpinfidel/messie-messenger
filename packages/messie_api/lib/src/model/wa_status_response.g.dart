// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'wa_status_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const WAStatusResponseStateEnum _$wAStatusResponseStateEnum_pending =
    const WAStatusResponseStateEnum._('pending');
const WAStatusResponseStateEnum _$wAStatusResponseStateEnum_scanned =
    const WAStatusResponseStateEnum._('scanned');
const WAStatusResponseStateEnum _$wAStatusResponseStateEnum_connected =
    const WAStatusResponseStateEnum._('connected');
const WAStatusResponseStateEnum _$wAStatusResponseStateEnum_failed =
    const WAStatusResponseStateEnum._('failed');

WAStatusResponseStateEnum _$wAStatusResponseStateEnumValueOf(String name) {
  switch (name) {
    case 'pending':
      return _$wAStatusResponseStateEnum_pending;
    case 'scanned':
      return _$wAStatusResponseStateEnum_scanned;
    case 'connected':
      return _$wAStatusResponseStateEnum_connected;
    case 'failed':
      return _$wAStatusResponseStateEnum_failed;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<WAStatusResponseStateEnum> _$wAStatusResponseStateEnumValues =
    BuiltSet<WAStatusResponseStateEnum>(const <WAStatusResponseStateEnum>[
  _$wAStatusResponseStateEnum_pending,
  _$wAStatusResponseStateEnum_scanned,
  _$wAStatusResponseStateEnum_connected,
  _$wAStatusResponseStateEnum_failed,
]);

Serializer<WAStatusResponseStateEnum> _$wAStatusResponseStateEnumSerializer =
    _$WAStatusResponseStateEnumSerializer();

class _$WAStatusResponseStateEnumSerializer
    implements PrimitiveSerializer<WAStatusResponseStateEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'pending': 'pending',
    'scanned': 'scanned',
    'connected': 'connected',
    'failed': 'failed',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'pending': 'pending',
    'scanned': 'scanned',
    'connected': 'connected',
    'failed': 'failed',
  };

  @override
  final Iterable<Type> types = const <Type>[WAStatusResponseStateEnum];
  @override
  final String wireName = 'WAStatusResponseStateEnum';

  @override
  Object serialize(Serializers serializers, WAStatusResponseStateEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  WAStatusResponseStateEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      WAStatusResponseStateEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$WAStatusResponse extends WAStatusResponse {
  @override
  final WAStatusResponseStateEnum state;
  @override
  final WAStatusResponseAccount? account;
  @override
  final String? error;

  factory _$WAStatusResponse(
          [void Function(WAStatusResponseBuilder)? updates]) =>
      (WAStatusResponseBuilder()..update(updates))._build();

  _$WAStatusResponse._({required this.state, this.account, this.error})
      : super._();
  @override
  WAStatusResponse rebuild(void Function(WAStatusResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WAStatusResponseBuilder toBuilder() =>
      WAStatusResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WAStatusResponse &&
        state == other.state &&
        account == other.account &&
        error == other.error;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, state.hashCode);
    _$hash = $jc(_$hash, account.hashCode);
    _$hash = $jc(_$hash, error.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WAStatusResponse')
          ..add('state', state)
          ..add('account', account)
          ..add('error', error))
        .toString();
  }
}

class WAStatusResponseBuilder
    implements Builder<WAStatusResponse, WAStatusResponseBuilder> {
  _$WAStatusResponse? _$v;

  WAStatusResponseStateEnum? _state;
  WAStatusResponseStateEnum? get state => _$this._state;
  set state(WAStatusResponseStateEnum? state) => _$this._state = state;

  WAStatusResponseAccountBuilder? _account;
  WAStatusResponseAccountBuilder get account =>
      _$this._account ??= WAStatusResponseAccountBuilder();
  set account(WAStatusResponseAccountBuilder? account) =>
      _$this._account = account;

  String? _error;
  String? get error => _$this._error;
  set error(String? error) => _$this._error = error;

  WAStatusResponseBuilder() {
    WAStatusResponse._defaults(this);
  }

  WAStatusResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _state = $v.state;
      _account = $v.account?.toBuilder();
      _error = $v.error;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WAStatusResponse other) {
    _$v = other as _$WAStatusResponse;
  }

  @override
  void update(void Function(WAStatusResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WAStatusResponse build() => _build();

  _$WAStatusResponse _build() {
    _$WAStatusResponse _$result;
    try {
      _$result = _$v ??
          _$WAStatusResponse._(
            state: BuiltValueNullFieldError.checkNotNull(
                state, r'WAStatusResponse', 'state'),
            account: _account?.build(),
            error: error,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'account';
        _account?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'WAStatusResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
