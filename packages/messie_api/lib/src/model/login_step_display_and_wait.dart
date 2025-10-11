//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:messie_api/src/model/login_step_display_and_wait_display_and_wait.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'login_step_display_and_wait.g.dart';

/// LoginStepDisplayAndWait
///
/// Properties:
/// * [type] 
/// * [displayAndWait] 
@BuiltValue()
abstract class LoginStepDisplayAndWait implements Built<LoginStepDisplayAndWait, LoginStepDisplayAndWaitBuilder> {
  @BuiltValueField(wireName: r'type')
  LoginStepDisplayAndWaitTypeEnum get type;
  // enum typeEnum {  display_and_wait,  };

  @BuiltValueField(wireName: r'display_and_wait')
  LoginStepDisplayAndWaitDisplayAndWait get displayAndWait;

  LoginStepDisplayAndWait._();

  factory LoginStepDisplayAndWait([void updates(LoginStepDisplayAndWaitBuilder b)]) = _$LoginStepDisplayAndWait;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LoginStepDisplayAndWaitBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LoginStepDisplayAndWait> get serializer => _$LoginStepDisplayAndWaitSerializer();
}

class _$LoginStepDisplayAndWaitSerializer implements PrimitiveSerializer<LoginStepDisplayAndWait> {
  @override
  final Iterable<Type> types = const [LoginStepDisplayAndWait, _$LoginStepDisplayAndWait];

  @override
  final String wireName = r'LoginStepDisplayAndWait';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LoginStepDisplayAndWait object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'type';
    yield serializers.serialize(
      object.type,
      specifiedType: const FullType(LoginStepDisplayAndWaitTypeEnum),
    );
    yield r'display_and_wait';
    yield serializers.serialize(
      object.displayAndWait,
      specifiedType: const FullType(LoginStepDisplayAndWaitDisplayAndWait),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    LoginStepDisplayAndWait object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LoginStepDisplayAndWaitBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(LoginStepDisplayAndWaitTypeEnum),
          ) as LoginStepDisplayAndWaitTypeEnum;
          result.type = valueDes;
          break;
        case r'display_and_wait':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(LoginStepDisplayAndWaitDisplayAndWait),
          ) as LoginStepDisplayAndWaitDisplayAndWait;
          result.displayAndWait.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LoginStepDisplayAndWait deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LoginStepDisplayAndWaitBuilder();
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

class LoginStepDisplayAndWaitTypeEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'display_and_wait')
  static const LoginStepDisplayAndWaitTypeEnum displayAndWait = _$loginStepDisplayAndWaitTypeEnum_displayAndWait;

  static Serializer<LoginStepDisplayAndWaitTypeEnum> get serializer => _$loginStepDisplayAndWaitTypeEnumSerializer;

  const LoginStepDisplayAndWaitTypeEnum._(String name): super(name);

  static BuiltSet<LoginStepDisplayAndWaitTypeEnum> get values => _$loginStepDisplayAndWaitTypeEnumValues;
  static LoginStepDisplayAndWaitTypeEnum valueOf(String name) => _$loginStepDisplayAndWaitTypeEnumValueOf(name);
}

