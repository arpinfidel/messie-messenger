//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:messie_api/src/model/bridge_whoami_login_profile.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'bridge_whoami_login.g.dart';

/// Minimal info about an individual login
///
/// Properties:
/// * [id] - Unique login ID defined by the bridge
/// * [name] - Human-friendly name of the login
/// * [state] - Optional state label for the login
/// * [profile] 
@BuiltValue()
abstract class BridgeWhoamiLogin implements Built<BridgeWhoamiLogin, BridgeWhoamiLoginBuilder> {
  /// Unique login ID defined by the bridge
  @BuiltValueField(wireName: r'id')
  String get id;

  /// Human-friendly name of the login
  @BuiltValueField(wireName: r'name')
  String get name;

  /// Optional state label for the login
  @BuiltValueField(wireName: r'state')
  String? get state;

  @BuiltValueField(wireName: r'profile')
  BridgeWhoamiLoginProfile? get profile;

  BridgeWhoamiLogin._();

  factory BridgeWhoamiLogin([void updates(BridgeWhoamiLoginBuilder b)]) = _$BridgeWhoamiLogin;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BridgeWhoamiLoginBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BridgeWhoamiLogin> get serializer => _$BridgeWhoamiLoginSerializer();
}

class _$BridgeWhoamiLoginSerializer implements PrimitiveSerializer<BridgeWhoamiLogin> {
  @override
  final Iterable<Type> types = const [BridgeWhoamiLogin, _$BridgeWhoamiLogin];

  @override
  final String wireName = r'BridgeWhoamiLogin';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BridgeWhoamiLogin object, {
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
    if (object.state != null) {
      yield r'state';
      yield serializers.serialize(
        object.state,
        specifiedType: const FullType(String),
      );
    }
    if (object.profile != null) {
      yield r'profile';
      yield serializers.serialize(
        object.profile,
        specifiedType: const FullType.nullable(BridgeWhoamiLoginProfile),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BridgeWhoamiLogin object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BridgeWhoamiLoginBuilder result,
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
        case r'state':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.state = valueDes;
          break;
        case r'profile':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(BridgeWhoamiLoginProfile),
          ) as BridgeWhoamiLoginProfile?;
          if (valueDes == null) continue;
          result.profile.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BridgeWhoamiLogin deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BridgeWhoamiLoginBuilder();
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

