//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:messie_api/src/model/bridge_account.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'bridge_connection.g.dart';

/// BridgeConnection
///
/// Properties:
/// * [provider] 
/// * [status] 
/// * [account] 
/// * [limits] 
@BuiltValue()
abstract class BridgeConnection implements Built<BridgeConnection, BridgeConnectionBuilder> {
  @BuiltValueField(wireName: r'provider')
  String get provider;

  @BuiltValueField(wireName: r'status')
  BridgeConnectionStatusEnum get status;
  // enum statusEnum {  not_connected,  connecting,  connected,  };

  @BuiltValueField(wireName: r'account')
  BridgeAccount? get account;

  @BuiltValueField(wireName: r'limits')
  BuiltMap<String, JsonObject?>? get limits;

  BridgeConnection._();

  factory BridgeConnection([void updates(BridgeConnectionBuilder b)]) = _$BridgeConnection;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BridgeConnectionBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BridgeConnection> get serializer => _$BridgeConnectionSerializer();
}

class _$BridgeConnectionSerializer implements PrimitiveSerializer<BridgeConnection> {
  @override
  final Iterable<Type> types = const [BridgeConnection, _$BridgeConnection];

  @override
  final String wireName = r'BridgeConnection';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BridgeConnection object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'provider';
    yield serializers.serialize(
      object.provider,
      specifiedType: const FullType(String),
    );
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(BridgeConnectionStatusEnum),
    );
    if (object.account != null) {
      yield r'account';
      yield serializers.serialize(
        object.account,
        specifiedType: const FullType(BridgeAccount),
      );
    }
    if (object.limits != null) {
      yield r'limits';
      yield serializers.serialize(
        object.limits,
        specifiedType: const FullType.nullable(BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BridgeConnection object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BridgeConnectionBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'provider':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.provider = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BridgeConnectionStatusEnum),
          ) as BridgeConnectionStatusEnum;
          result.status = valueDes;
          break;
        case r'account':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BridgeAccount),
          ) as BridgeAccount;
          result.account.replace(valueDes);
          break;
        case r'limits':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
          ) as BuiltMap<String, JsonObject?>?;
          if (valueDes == null) continue;
          result.limits.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BridgeConnection deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BridgeConnectionBuilder();
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

class BridgeConnectionStatusEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'not_connected')
  static const BridgeConnectionStatusEnum notConnected = _$bridgeConnectionStatusEnum_notConnected;
  @BuiltValueEnumConst(wireName: r'connecting')
  static const BridgeConnectionStatusEnum connecting = _$bridgeConnectionStatusEnum_connecting;
  @BuiltValueEnumConst(wireName: r'connected')
  static const BridgeConnectionStatusEnum connected = _$bridgeConnectionStatusEnum_connected;

  static Serializer<BridgeConnectionStatusEnum> get serializer => _$bridgeConnectionStatusEnumSerializer;

  const BridgeConnectionStatusEnum._(String name): super(name);

  static BuiltSet<BridgeConnectionStatusEnum> get values => _$bridgeConnectionStatusEnumValues;
  static BridgeConnectionStatusEnum valueOf(String name) => _$bridgeConnectionStatusEnumValueOf(name);
}

