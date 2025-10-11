//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'wa_start_response.g.dart';

/// WAStartResponse
///
/// Properties:
/// * [connectionId] 
/// * [method] 
/// * [qrAscii] - ASCII QR for display in terminals; optional
/// * [code] - Pairing code string; optional
/// * [expiresAt] 
@BuiltValue()
abstract class WAStartResponse implements Built<WAStartResponse, WAStartResponseBuilder> {
  @BuiltValueField(wireName: r'connectionId')
  String get connectionId;

  @BuiltValueField(wireName: r'method')
  WAStartResponseMethodEnum get method;
  // enum methodEnum {  qr,  code,  };

  /// ASCII QR for display in terminals; optional
  @BuiltValueField(wireName: r'qrAscii')
  String? get qrAscii;

  /// Pairing code string; optional
  @BuiltValueField(wireName: r'code')
  String? get code;

  @BuiltValueField(wireName: r'expiresAt')
  DateTime get expiresAt;

  WAStartResponse._();

  factory WAStartResponse([void updates(WAStartResponseBuilder b)]) = _$WAStartResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WAStartResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WAStartResponse> get serializer => _$WAStartResponseSerializer();
}

class _$WAStartResponseSerializer implements PrimitiveSerializer<WAStartResponse> {
  @override
  final Iterable<Type> types = const [WAStartResponse, _$WAStartResponse];

  @override
  final String wireName = r'WAStartResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WAStartResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'connectionId';
    yield serializers.serialize(
      object.connectionId,
      specifiedType: const FullType(String),
    );
    yield r'method';
    yield serializers.serialize(
      object.method,
      specifiedType: const FullType(WAStartResponseMethodEnum),
    );
    if (object.qrAscii != null) {
      yield r'qrAscii';
      yield serializers.serialize(
        object.qrAscii,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.code != null) {
      yield r'code';
      yield serializers.serialize(
        object.code,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'expiresAt';
    yield serializers.serialize(
      object.expiresAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    WAStartResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required WAStartResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'connectionId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.connectionId = valueDes;
          break;
        case r'method':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(WAStartResponseMethodEnum),
          ) as WAStartResponseMethodEnum;
          result.method = valueDes;
          break;
        case r'qrAscii':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.qrAscii = valueDes;
          break;
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.code = valueDes;
          break;
        case r'expiresAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.expiresAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  WAStartResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WAStartResponseBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}

class WAStartResponseMethodEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'qr')
  static const WAStartResponseMethodEnum qr = _$wAStartResponseMethodEnum_qr;
  @BuiltValueEnumConst(wireName: r'code')
  static const WAStartResponseMethodEnum code = _$wAStartResponseMethodEnum_code;

  static Serializer<WAStartResponseMethodEnum> get serializer => _$wAStartResponseMethodEnumSerializer;

  const WAStartResponseMethodEnum._(String name): super(name);

  static BuiltSet<WAStartResponseMethodEnum> get values => _$wAStartResponseMethodEnumValues;
  static WAStartResponseMethodEnum valueOf(String name) => _$wAStartResponseMethodEnumValueOf(name);
}

