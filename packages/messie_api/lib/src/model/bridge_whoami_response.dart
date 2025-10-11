//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:messie_api/src/model/bridge_name.dart';
import 'package:built_collection/built_collection.dart';
import 'package:messie_api/src/model/bridge_login_flow.dart';
import 'package:messie_api/src/model/bridge_whoami_login.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'bridge_whoami_response.g.dart';

/// Provider metadata and current user logins
///
/// Properties:
/// * [homeserver] 
/// * [bridgeBot] 
/// * [commandPrefix] 
/// * [network] 
/// * [loginFlows] 
/// * [logins] 
@BuiltValue()
abstract class BridgeWhoamiResponse implements Built<BridgeWhoamiResponse, BridgeWhoamiResponseBuilder> {
  @BuiltValueField(wireName: r'homeserver')
  String? get homeserver;

  @BuiltValueField(wireName: r'bridge_bot')
  String? get bridgeBot;

  @BuiltValueField(wireName: r'command_prefix')
  String? get commandPrefix;

  @BuiltValueField(wireName: r'network')
  BridgeName? get network;

  @BuiltValueField(wireName: r'login_flows')
  BuiltList<BridgeLoginFlow>? get loginFlows;

  @BuiltValueField(wireName: r'logins')
  BuiltList<BridgeWhoamiLogin>? get logins;

  BridgeWhoamiResponse._();

  factory BridgeWhoamiResponse([void updates(BridgeWhoamiResponseBuilder b)]) = _$BridgeWhoamiResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BridgeWhoamiResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BridgeWhoamiResponse> get serializer => _$BridgeWhoamiResponseSerializer();
}

class _$BridgeWhoamiResponseSerializer implements PrimitiveSerializer<BridgeWhoamiResponse> {
  @override
  final Iterable<Type> types = const [BridgeWhoamiResponse, _$BridgeWhoamiResponse];

  @override
  final String wireName = r'BridgeWhoamiResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BridgeWhoamiResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.homeserver != null) {
      yield r'homeserver';
      yield serializers.serialize(
        object.homeserver,
        specifiedType: const FullType(String),
      );
    }
    if (object.bridgeBot != null) {
      yield r'bridge_bot';
      yield serializers.serialize(
        object.bridgeBot,
        specifiedType: const FullType(String),
      );
    }
    if (object.commandPrefix != null) {
      yield r'command_prefix';
      yield serializers.serialize(
        object.commandPrefix,
        specifiedType: const FullType(String),
      );
    }
    if (object.network != null) {
      yield r'network';
      yield serializers.serialize(
        object.network,
        specifiedType: const FullType(BridgeName),
      );
    }
    if (object.loginFlows != null) {
      yield r'login_flows';
      yield serializers.serialize(
        object.loginFlows,
        specifiedType: const FullType(BuiltList, [FullType(BridgeLoginFlow)]),
      );
    }
    if (object.logins != null) {
      yield r'logins';
      yield serializers.serialize(
        object.logins,
        specifiedType: const FullType(BuiltList, [FullType(BridgeWhoamiLogin)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    BridgeWhoamiResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BridgeWhoamiResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'homeserver':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.homeserver = valueDes;
          break;
        case r'bridge_bot':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.bridgeBot = valueDes;
          break;
        case r'command_prefix':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.commandPrefix = valueDes;
          break;
        case r'network':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BridgeName),
          ) as BridgeName;
          result.network.replace(valueDes);
          break;
        case r'login_flows':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(BridgeLoginFlow)]),
          ) as BuiltList<BridgeLoginFlow>;
          result.loginFlows.replace(valueDes);
          break;
        case r'logins':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(BridgeWhoamiLogin)]),
          ) as BuiltList<BridgeWhoamiLogin>;
          result.logins.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BridgeWhoamiResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BridgeWhoamiResponseBuilder();
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

