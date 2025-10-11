//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'bridge_name.g.dart';

/// Info about the bridged network
///
/// Properties:
/// * [displayname] 
/// * [networkUrl] 
/// * [networkIcon] 
/// * [networkId] 
/// * [beeperBridgeType] 
@BuiltValue()
abstract class BridgeName implements Built<BridgeName, BridgeNameBuilder> {
  @BuiltValueField(wireName: r'displayname')
  String get displayname;

  @BuiltValueField(wireName: r'network_url')
  String get networkUrl;

  @BuiltValueField(wireName: r'network_icon')
  String get networkIcon;

  @BuiltValueField(wireName: r'network_id')
  String get networkId;

  @BuiltValueField(wireName: r'beeper_bridge_type')
  String? get beeperBridgeType;

  BridgeName._();

  factory BridgeName([void updates(BridgeNameBuilder b)]) = _$BridgeName;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BridgeNameBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BridgeName> get serializer => _$BridgeNameSerializer();
}

class _$BridgeNameSerializer implements PrimitiveSerializer<BridgeName> {
  @override
  final Iterable<Type> types = const [BridgeName, _$BridgeName];

  @override
  final String wireName = r'BridgeName';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BridgeName object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'displayname';
    yield serializers.serialize(
      object.displayname,
      specifiedType: const FullType(String),
    );
    yield r'network_url';
    yield serializers.serialize(
      object.networkUrl,
      specifiedType: const FullType(String),
    );
    yield r'network_icon';
    yield serializers.serialize(
      object.networkIcon,
      specifiedType: const FullType(String),
    );
    yield r'network_id';
    yield serializers.serialize(
      object.networkId,
      specifiedType: const FullType(String),
    );
    if (object.beeperBridgeType != null) {
      yield r'beeper_bridge_type';
      yield serializers.serialize(
        object.beeperBridgeType,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BridgeName object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BridgeNameBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'displayname':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.displayname = valueDes;
          break;
        case r'network_url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.networkUrl = valueDes;
          break;
        case r'network_icon':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.networkIcon = valueDes;
          break;
        case r'network_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.networkId = valueDes;
          break;
        case r'beeper_bridge_type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.beeperBridgeType = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BridgeName deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BridgeNameBuilder();
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

