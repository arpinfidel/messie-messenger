// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'wa_start_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const WAStartResponseMethodEnum _$wAStartResponseMethodEnum_qr =
    const WAStartResponseMethodEnum._('qr');
const WAStartResponseMethodEnum _$wAStartResponseMethodEnum_code =
    const WAStartResponseMethodEnum._('code');

WAStartResponseMethodEnum _$wAStartResponseMethodEnumValueOf(String name) {
  switch (name) {
    case 'qr':
      return _$wAStartResponseMethodEnum_qr;
    case 'code':
      return _$wAStartResponseMethodEnum_code;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<WAStartResponseMethodEnum> _$wAStartResponseMethodEnumValues =
    BuiltSet<WAStartResponseMethodEnum>(const <WAStartResponseMethodEnum>[
  _$wAStartResponseMethodEnum_qr,
  _$wAStartResponseMethodEnum_code,
]);

Serializer<WAStartResponseMethodEnum> _$wAStartResponseMethodEnumSerializer =
    _$WAStartResponseMethodEnumSerializer();

class _$WAStartResponseMethodEnumSerializer
    implements PrimitiveSerializer<WAStartResponseMethodEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'qr': 'qr',
    'code': 'code',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'qr': 'qr',
    'code': 'code',
  };

  @override
  final Iterable<Type> types = const <Type>[WAStartResponseMethodEnum];
  @override
  final String wireName = 'WAStartResponseMethodEnum';

  @override
  Object serialize(Serializers serializers, WAStartResponseMethodEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  WAStartResponseMethodEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      WAStartResponseMethodEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$WAStartResponse extends WAStartResponse {
  @override
  final String connectionId;
  @override
  final WAStartResponseMethodEnum method;
  @override
  final String? qrAscii;
  @override
  final String? code;
  @override
  final DateTime expiresAt;

  factory _$WAStartResponse([void Function(WAStartResponseBuilder)? updates]) =>
      (WAStartResponseBuilder()..update(updates))._build();

  _$WAStartResponse._(
      {required this.connectionId,
      required this.method,
      this.qrAscii,
      this.code,
      required this.expiresAt})
      : super._();
  @override
  WAStartResponse rebuild(void Function(WAStartResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  WAStartResponseBuilder toBuilder() => WAStartResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is WAStartResponse &&
        connectionId == other.connectionId &&
        method == other.method &&
        qrAscii == other.qrAscii &&
        code == other.code &&
        expiresAt == other.expiresAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, connectionId.hashCode);
    _$hash = $jc(_$hash, method.hashCode);
    _$hash = $jc(_$hash, qrAscii.hashCode);
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, expiresAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'WAStartResponse')
          ..add('connectionId', connectionId)
          ..add('method', method)
          ..add('qrAscii', qrAscii)
          ..add('code', code)
          ..add('expiresAt', expiresAt))
        .toString();
  }
}

class WAStartResponseBuilder
    implements Builder<WAStartResponse, WAStartResponseBuilder> {
  _$WAStartResponse? _$v;

  String? _connectionId;
  String? get connectionId => _$this._connectionId;
  set connectionId(String? connectionId) => _$this._connectionId = connectionId;

  WAStartResponseMethodEnum? _method;
  WAStartResponseMethodEnum? get method => _$this._method;
  set method(WAStartResponseMethodEnum? method) => _$this._method = method;

  String? _qrAscii;
  String? get qrAscii => _$this._qrAscii;
  set qrAscii(String? qrAscii) => _$this._qrAscii = qrAscii;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  DateTime? _expiresAt;
  DateTime? get expiresAt => _$this._expiresAt;
  set expiresAt(DateTime? expiresAt) => _$this._expiresAt = expiresAt;

  WAStartResponseBuilder() {
    WAStartResponse._defaults(this);
  }

  WAStartResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _connectionId = $v.connectionId;
      _method = $v.method;
      _qrAscii = $v.qrAscii;
      _code = $v.code;
      _expiresAt = $v.expiresAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(WAStartResponse other) {
    _$v = other as _$WAStartResponse;
  }

  @override
  void update(void Function(WAStartResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  WAStartResponse build() => _build();

  _$WAStartResponse _build() {
    final _$result = _$v ??
        _$WAStartResponse._(
          connectionId: BuiltValueNullFieldError.checkNotNull(
              connectionId, r'WAStartResponse', 'connectionId'),
          method: BuiltValueNullFieldError.checkNotNull(
              method, r'WAStartResponse', 'method'),
          qrAscii: qrAscii,
          code: code,
          expiresAt: BuiltValueNullFieldError.checkNotNull(
              expiresAt, r'WAStartResponse', 'expiresAt'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
