//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'bridge_whoami_login_profile.g.dart';

/// BridgeWhoamiLoginProfile
///
/// Properties:
/// * [displayName] 
/// * [externalId] 
@BuiltValue()
abstract class BridgeWhoamiLoginProfile implements Built<BridgeWhoamiLoginProfile, BridgeWhoamiLoginProfileBuilder> {
  @BuiltValueField(wireName: r'displayName')
  String? get displayName;

  @BuiltValueField(wireName: r'externalId')
  String? get externalId;

  BridgeWhoamiLoginProfile._();

  factory BridgeWhoamiLoginProfile([void updates(BridgeWhoamiLoginProfileBuilder b)]) = _$BridgeWhoamiLoginProfile;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BridgeWhoamiLoginProfileBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BridgeWhoamiLoginProfile> get serializer => _$BridgeWhoamiLoginProfileSerializer();
}

class _$BridgeWhoamiLoginProfileSerializer implements PrimitiveSerializer<BridgeWhoamiLoginProfile> {
  @override
  final Iterable<Type> types = const [BridgeWhoamiLoginProfile, _$BridgeWhoamiLoginProfile];

  @override
  final String wireName = r'BridgeWhoamiLoginProfile';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BridgeWhoamiLoginProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.displayName != null) {
      yield r'displayName';
      yield serializers.serialize(
        object.displayName,
        specifiedType: const FullType(String),
      );
    }
    if (object.externalId != null) {
      yield r'externalId';
      yield serializers.serialize(
        object.externalId,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BridgeWhoamiLoginProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BridgeWhoamiLoginProfileBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'displayName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.displayName = valueDes;
          break;
        case r'externalId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.externalId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BridgeWhoamiLoginProfile deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BridgeWhoamiLoginProfileBuilder();
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

