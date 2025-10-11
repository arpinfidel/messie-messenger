//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:messie_api/src/model/wa_status_response_account.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'wa_status_response.g.dart';

/// WAStatusResponse
///
/// Properties:
/// * [state] 
/// * [account] 
/// * [error] 
@BuiltValue()
abstract class WAStatusResponse implements Built<WAStatusResponse, WAStatusResponseBuilder> {
  @BuiltValueField(wireName: r'state')
  WAStatusResponseStateEnum get state;
  // enum stateEnum {  pending,  scanned,  connected,  failed,  };

  @BuiltValueField(wireName: r'account')
  WAStatusResponseAccount? get account;

  @BuiltValueField(wireName: r'error')
  String? get error;

  WAStatusResponse._();

  factory WAStatusResponse([void updates(WAStatusResponseBuilder b)]) = _$WAStatusResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WAStatusResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WAStatusResponse> get serializer => _$WAStatusResponseSerializer();
}

class _$WAStatusResponseSerializer implements PrimitiveSerializer<WAStatusResponse> {
  @override
  final Iterable<Type> types = const [WAStatusResponse, _$WAStatusResponse];

  @override
  final String wireName = r'WAStatusResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WAStatusResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'state';
    yield serializers.serialize(
      object.state,
      specifiedType: const FullType(WAStatusResponseStateEnum),
    );
    if (object.account != null) {
      yield r'account';
      yield serializers.serialize(
        object.account,
        specifiedType: const FullType.nullable(WAStatusResponseAccount),
      );
    }
    if (object.error != null) {
      yield r'error';
      yield serializers.serialize(
        object.error,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    WAStatusResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required WAStatusResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'state':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(WAStatusResponseStateEnum),
          ) as WAStatusResponseStateEnum;
          result.state = valueDes;
          break;
        case r'account':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(WAStatusResponseAccount),
          ) as WAStatusResponseAccount?;
          if (valueDes == null) continue;
          result.account.replace(valueDes);
          break;
        case r'error':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.error = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  WAStatusResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WAStatusResponseBuilder();
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

class WAStatusResponseStateEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'pending')
  static const WAStatusResponseStateEnum pending = _$wAStatusResponseStateEnum_pending;
  @BuiltValueEnumConst(wireName: r'scanned')
  static const WAStatusResponseStateEnum scanned = _$wAStatusResponseStateEnum_scanned;
  @BuiltValueEnumConst(wireName: r'connected')
  static const WAStatusResponseStateEnum connected = _$wAStatusResponseStateEnum_connected;
  @BuiltValueEnumConst(wireName: r'failed')
  static const WAStatusResponseStateEnum failed = _$wAStatusResponseStateEnum_failed;

  static Serializer<WAStatusResponseStateEnum> get serializer => _$wAStatusResponseStateEnumSerializer;

  const WAStatusResponseStateEnum._(String name): super(name);

  static BuiltSet<WAStatusResponseStateEnum> get values => _$wAStatusResponseStateEnumValues;
  static WAStatusResponseStateEnum valueOf(String name) => _$wAStatusResponseStateEnumValueOf(name);
}

