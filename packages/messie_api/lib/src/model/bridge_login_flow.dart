//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'bridge_login_flow.g.dart';

/// A login flow that can be used to sign into the remote network.
///
/// Properties:
/// * [id] 
/// * [name] 
/// * [description] 
@BuiltValue()
abstract class BridgeLoginFlow implements Built<BridgeLoginFlow, BridgeLoginFlowBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'description')
  String get description;

  BridgeLoginFlow._();

  factory BridgeLoginFlow([void updates(BridgeLoginFlowBuilder b)]) = _$BridgeLoginFlow;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BridgeLoginFlowBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BridgeLoginFlow> get serializer => _$BridgeLoginFlowSerializer();
}

class _$BridgeLoginFlowSerializer implements PrimitiveSerializer<BridgeLoginFlow> {
  @override
  final Iterable<Type> types = const [BridgeLoginFlow, _$BridgeLoginFlow];

  @override
  final String wireName = r'BridgeLoginFlow';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BridgeLoginFlow object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'description';
    yield serializers.serialize(
      object.description,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    BridgeLoginFlow object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BridgeLoginFlowBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'description':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.description = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BridgeLoginFlow deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BridgeLoginFlowBuilder();
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

