//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'bridge_state.g.dart';

/// Connection status of an individual login
///
/// Properties:
/// * [stateEvent] 
/// * [timestamp] - Unix time in milliseconds
/// * [error] 
/// * [message] 
/// * [reason] 
/// * [info] 
@BuiltValue()
abstract class BridgeState implements Built<BridgeState, BridgeStateBuilder> {
  @BuiltValueField(wireName: r'state_event')
  BridgeStateStateEventEnum get stateEvent;
  // enum stateEventEnum {  CONNECTING,  CONNECTED,  TRANSIENT_DISCONNECT,  BAD_CREDENTIALS,  UNKNOWN_ERROR,  };

  /// Unix time in milliseconds
  @BuiltValueField(wireName: r'timestamp')
  double get timestamp;

  @BuiltValueField(wireName: r'error')
  String? get error;

  @BuiltValueField(wireName: r'message')
  String? get message;

  @BuiltValueField(wireName: r'reason')
  String? get reason;

  @BuiltValueField(wireName: r'info')
  BuiltMap<String, JsonObject?>? get info;

  BridgeState._();

  factory BridgeState([void updates(BridgeStateBuilder b)]) = _$BridgeState;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BridgeStateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BridgeState> get serializer => _$BridgeStateSerializer();
}

class _$BridgeStateSerializer implements PrimitiveSerializer<BridgeState> {
  @override
  final Iterable<Type> types = const [BridgeState, _$BridgeState];

  @override
  final String wireName = r'BridgeState';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BridgeState object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'state_event';
    yield serializers.serialize(
      object.stateEvent,
      specifiedType: const FullType(BridgeStateStateEventEnum),
    );
    yield r'timestamp';
    yield serializers.serialize(
      object.timestamp,
      specifiedType: const FullType(double),
    );
    if (object.error != null) {
      yield r'error';
      yield serializers.serialize(
        object.error,
        specifiedType: const FullType(String),
      );
    }
    if (object.message != null) {
      yield r'message';
      yield serializers.serialize(
        object.message,
        specifiedType: const FullType(String),
      );
    }
    if (object.reason != null) {
      yield r'reason';
      yield serializers.serialize(
        object.reason,
        specifiedType: const FullType(String),
      );
    }
    if (object.info != null) {
      yield r'info';
      yield serializers.serialize(
        object.info,
        specifiedType: const FullType(BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BridgeState object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BridgeStateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'state_event':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BridgeStateStateEventEnum),
          ) as BridgeStateStateEventEnum;
          result.stateEvent = valueDes;
          break;
        case r'timestamp':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.timestamp = valueDes;
          break;
        case r'error':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.error = valueDes;
          break;
        case r'message':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.message = valueDes;
          break;
        case r'reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.reason = valueDes;
          break;
        case r'info':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
          ) as BuiltMap<String, JsonObject?>;
          result.info.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BridgeState deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BridgeStateBuilder();
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

class BridgeStateStateEventEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'CONNECTING')
  static const BridgeStateStateEventEnum CONNECTING = _$bridgeStateStateEventEnum_CONNECTING;
  @BuiltValueEnumConst(wireName: r'CONNECTED')
  static const BridgeStateStateEventEnum CONNECTED = _$bridgeStateStateEventEnum_CONNECTED;
  @BuiltValueEnumConst(wireName: r'TRANSIENT_DISCONNECT')
  static const BridgeStateStateEventEnum TRANSIENT_DISCONNECT = _$bridgeStateStateEventEnum_TRANSIENT_DISCONNECT;
  @BuiltValueEnumConst(wireName: r'BAD_CREDENTIALS')
  static const BridgeStateStateEventEnum BAD_CREDENTIALS = _$bridgeStateStateEventEnum_BAD_CREDENTIALS;
  @BuiltValueEnumConst(wireName: r'UNKNOWN_ERROR')
  static const BridgeStateStateEventEnum UNKNOWN_ERROR = _$bridgeStateStateEventEnum_UNKNOWN_ERROR;

  static Serializer<BridgeStateStateEventEnum> get serializer => _$bridgeStateStateEventEnumSerializer;

  const BridgeStateStateEventEnum._(String name): super(name);

  static BuiltSet<BridgeStateStateEventEnum> get values => _$bridgeStateStateEventEnumValues;
  static BridgeStateStateEventEnum valueOf(String name) => _$bridgeStateStateEventEnumValueOf(name);
}

