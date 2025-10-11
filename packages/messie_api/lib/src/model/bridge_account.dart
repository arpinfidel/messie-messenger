//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'bridge_account.g.dart';

/// BridgeAccount
///
/// Properties:
/// * [externalId] 
/// * [displayName] 
@BuiltValue()
abstract class BridgeAccount implements Built<BridgeAccount, BridgeAccountBuilder> {
  @BuiltValueField(wireName: r'externalId')
  String? get externalId;

  @BuiltValueField(wireName: r'displayName')
  String? get displayName;

  BridgeAccount._();

  factory BridgeAccount([void updates(BridgeAccountBuilder b)]) = _$BridgeAccount;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BridgeAccountBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BridgeAccount> get serializer => _$BridgeAccountSerializer();
}

class _$BridgeAccountSerializer implements PrimitiveSerializer<BridgeAccount> {
  @override
  final Iterable<Type> types = const [BridgeAccount, _$BridgeAccount];

  @override
  final String wireName = r'BridgeAccount';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BridgeAccount object, {
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
    BridgeAccount object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BridgeAccountBuilder result,
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
  BridgeAccount deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BridgeAccountBuilder();
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

