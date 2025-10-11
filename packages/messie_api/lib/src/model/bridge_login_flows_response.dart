//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:messie_api/src/model/bridge_login_flow.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'bridge_login_flows_response.g.dart';

/// BridgeLoginFlowsResponse
///
/// Properties:
/// * [flows] 
@BuiltValue()
abstract class BridgeLoginFlowsResponse implements Built<BridgeLoginFlowsResponse, BridgeLoginFlowsResponseBuilder> {
  @BuiltValueField(wireName: r'flows')
  BuiltList<BridgeLoginFlow>? get flows;

  BridgeLoginFlowsResponse._();

  factory BridgeLoginFlowsResponse([void updates(BridgeLoginFlowsResponseBuilder b)]) = _$BridgeLoginFlowsResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BridgeLoginFlowsResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BridgeLoginFlowsResponse> get serializer => _$BridgeLoginFlowsResponseSerializer();
}

class _$BridgeLoginFlowsResponseSerializer implements PrimitiveSerializer<BridgeLoginFlowsResponse> {
  @override
  final Iterable<Type> types = const [BridgeLoginFlowsResponse, _$BridgeLoginFlowsResponse];

  @override
  final String wireName = r'BridgeLoginFlowsResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BridgeLoginFlowsResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.flows != null) {
      yield r'flows';
      yield serializers.serialize(
        object.flows,
        specifiedType: const FullType(BuiltList, [FullType(BridgeLoginFlow)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BridgeLoginFlowsResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BridgeLoginFlowsResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'flows':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(BridgeLoginFlow)]),
          ) as BuiltList<BridgeLoginFlow>;
          result.flows.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BridgeLoginFlowsResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BridgeLoginFlowsResponseBuilder();
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

