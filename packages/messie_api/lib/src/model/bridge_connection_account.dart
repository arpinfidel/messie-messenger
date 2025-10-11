//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'bridge_connection_account.g.dart';

/// BridgeConnectionAccount
///
/// Properties:
/// * [externalId] 
/// * [displayName] 
@BuiltValue()
abstract class BridgeConnectionAccount implements Built<BridgeConnectionAccount, BridgeConnectionAccountBuilder> {
  @BuiltValueField(wireName: r'externalId')
  String? get externalId;

  @BuiltValueField(wireName: r'displayName')
  String? get displayName;

  BridgeConnectionAccount._();

  factory BridgeConnectionAccount([void updates(BridgeConnectionAccountBuilder b)]) = _$BridgeConnectionAccount;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BridgeConnectionAccountBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BridgeConnectionAccount> get serializer => _$BridgeConnectionAccountSerializer();
}

class _$BridgeConnectionAccountSerializer implements PrimitiveSerializer<BridgeConnectionAccount> {
  @override
  final Iterable<Type> types = const [BridgeConnectionAccount, _$BridgeConnectionAccount];

  @override
  final String wireName = r'BridgeConnectionAccount';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BridgeConnectionAccount object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.externalId != null) {
      yield r'externalId';
      yield serializers.serialize(
        object.externalId,
        specifiedType: const FullType(String),
      );
    }
    if (object.displayName != null) {
      yield r'displayName';
      yield serializers.serialize(
        object.displayName,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BridgeConnectionAccount object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BridgeConnectionAccountBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'externalId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.externalId = valueDes;
          break;
        case r'displayName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.displayName = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BridgeConnectionAccount deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BridgeConnectionAccountBuilder();
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

