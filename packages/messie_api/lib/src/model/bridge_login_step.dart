//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:messie_api/src/model/login_step_complete_complete.dart';
import 'package:messie_api/src/model/login_step_complete.dart';
import 'package:messie_api/src/model/login_step_user_input_user_input.dart';
import 'package:built_collection/built_collection.dart';
import 'package:messie_api/src/model/login_step_display_and_wait_display_and_wait.dart';
import 'package:messie_api/src/model/login_step_display_and_wait.dart';
import 'package:messie_api/src/model/login_step_cookies.dart';
import 'package:messie_api/src/model/login_step_cookies_cookies.dart';
import 'package:messie_api/src/model/login_step_user_input.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'package:one_of/one_of.dart';

part 'bridge_login_step.g.dart';

/// BridgeLoginStep
///
/// Properties:
/// * [type] 
/// * [displayAndWait] 
/// * [userInput] 
/// * [cookies] 
/// * [complete] 
@BuiltValue()
abstract class BridgeLoginStep implements Built<BridgeLoginStep, BridgeLoginStepBuilder> {
  /// One Of [LoginStepComplete], [LoginStepCookies], [LoginStepDisplayAndWait], [LoginStepUserInput]
  OneOf get oneOf;

  static const String discriminatorFieldName = r'type';

  static const Map<String, Type> discriminatorMapping = {
    r'complete': LoginStepComplete,
    r'cookies': LoginStepCookies,
    r'display_and_wait': LoginStepDisplayAndWait,
    r'user_input': LoginStepUserInput,
  };

  BridgeLoginStep._();

  factory BridgeLoginStep([void updates(BridgeLoginStepBuilder b)]) = _$BridgeLoginStep;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BridgeLoginStepBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BridgeLoginStep> get serializer => _$BridgeLoginStepSerializer();
}

extension BridgeLoginStepDiscriminatorExt on BridgeLoginStep {
    String? get discriminatorValue {
        if (this is LoginStepComplete) {
            return r'complete';
        }
        if (this is LoginStepCookies) {
            return r'cookies';
        }
        if (this is LoginStepDisplayAndWait) {
            return r'display_and_wait';
        }
        if (this is LoginStepUserInput) {
            return r'user_input';
        }
        return null;
    }
}
extension BridgeLoginStepBuilderDiscriminatorExt on BridgeLoginStepBuilder {
    String? get discriminatorValue {
        if (this is LoginStepCompleteBuilder) {
            return r'complete';
        }
        if (this is LoginStepCookiesBuilder) {
            return r'cookies';
        }
        if (this is LoginStepDisplayAndWaitBuilder) {
            return r'display_and_wait';
        }
        if (this is LoginStepUserInputBuilder) {
            return r'user_input';
        }
        return null;
    }
}

class _$BridgeLoginStepSerializer implements PrimitiveSerializer<BridgeLoginStep> {
  @override
  final Iterable<Type> types = const [BridgeLoginStep, _$BridgeLoginStep];

  @override
  final String wireName = r'BridgeLoginStep';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BridgeLoginStep object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
  }

  @override
  Object serialize(
    Serializers serializers,
    BridgeLoginStep object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final oneOf = object.oneOf;
    return serializers.serialize(oneOf.value, specifiedType: FullType(oneOf.valueType))!;
  }

  @override
  BridgeLoginStep deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BridgeLoginStepBuilder();
    Object? oneOfDataSrc;
    final serializedList = (serialized as Iterable<Object?>).toList();
    final discIndex = serializedList.indexOf(BridgeLoginStep.discriminatorFieldName) + 1;
    final discValue = serializers.deserialize(serializedList[discIndex], specifiedType: FullType(String)) as String;
    oneOfDataSrc = serialized;
    final oneOfTypes = [LoginStepComplete, LoginStepCookies, LoginStepDisplayAndWait, LoginStepUserInput, ];
    Object oneOfResult;
    Type oneOfType;
    switch (discValue) {
      case r'complete':
        oneOfResult = serializers.deserialize(
          oneOfDataSrc,
          specifiedType: FullType(LoginStepComplete),
        ) as LoginStepComplete;
        oneOfType = LoginStepComplete;
        break;
      case r'cookies':
        oneOfResult = serializers.deserialize(
          oneOfDataSrc,
          specifiedType: FullType(LoginStepCookies),
        ) as LoginStepCookies;
        oneOfType = LoginStepCookies;
        break;
      case r'display_and_wait':
        oneOfResult = serializers.deserialize(
          oneOfDataSrc,
          specifiedType: FullType(LoginStepDisplayAndWait),
        ) as LoginStepDisplayAndWait;
        oneOfType = LoginStepDisplayAndWait;
        break;
      case r'user_input':
        oneOfResult = serializers.deserialize(
          oneOfDataSrc,
          specifiedType: FullType(LoginStepUserInput),
        ) as LoginStepUserInput;
        oneOfType = LoginStepUserInput;
        break;
      default:
        throw UnsupportedError("Couldn't deserialize oneOf for the discriminator value: ${discValue}");
    }
    result.oneOf = OneOfDynamic(typeIndex: oneOfTypes.indexOf(oneOfType), types: oneOfTypes, value: oneOfResult);
    return result.build();
  }
}

class BridgeLoginStepTypeEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'display_and_wait')
  static const BridgeLoginStepTypeEnum displayAndWait = _$bridgeLoginStepTypeEnum_displayAndWait;
  @BuiltValueEnumConst(wireName: r'user_input')
  static const BridgeLoginStepTypeEnum userInput = _$bridgeLoginStepTypeEnum_userInput;
  @BuiltValueEnumConst(wireName: r'cookies')
  static const BridgeLoginStepTypeEnum cookies = _$bridgeLoginStepTypeEnum_cookies;
  @BuiltValueEnumConst(wireName: r'complete')
  static const BridgeLoginStepTypeEnum complete = _$bridgeLoginStepTypeEnum_complete;

  static Serializer<BridgeLoginStepTypeEnum> get serializer => _$bridgeLoginStepTypeEnumSerializer;

  const BridgeLoginStepTypeEnum._(String name): super(name);

  static BuiltSet<BridgeLoginStepTypeEnum> get values => _$bridgeLoginStepTypeEnumValues;
  static BridgeLoginStepTypeEnum valueOf(String name) => _$bridgeLoginStepTypeEnumValueOf(name);
}

