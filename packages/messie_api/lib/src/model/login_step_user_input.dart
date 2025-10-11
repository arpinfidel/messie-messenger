//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:messie_api/src/model/login_step_user_input_user_input.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'login_step_user_input.g.dart';

/// LoginStepUserInput
///
/// Properties:
/// * [type] 
/// * [userInput] 
@BuiltValue()
abstract class LoginStepUserInput implements Built<LoginStepUserInput, LoginStepUserInputBuilder> {
  @BuiltValueField(wireName: r'type')
  LoginStepUserInputTypeEnum get type;
  // enum typeEnum {  user_input,  };

  @BuiltValueField(wireName: r'user_input')
  LoginStepUserInputUserInput get userInput;

  LoginStepUserInput._();

  factory LoginStepUserInput([void updates(LoginStepUserInputBuilder b)]) = _$LoginStepUserInput;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LoginStepUserInputBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LoginStepUserInput> get serializer => _$LoginStepUserInputSerializer();
}

class _$LoginStepUserInputSerializer implements PrimitiveSerializer<LoginStepUserInput> {
  @override
  final Iterable<Type> types = const [LoginStepUserInput, _$LoginStepUserInput];

  @override
  final String wireName = r'LoginStepUserInput';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LoginStepUserInput object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'type';
    yield serializers.serialize(
      object.type,
      specifiedType: const FullType(LoginStepUserInputTypeEnum),
    );
    yield r'user_input';
    yield serializers.serialize(
      object.userInput,
      specifiedType: const FullType(LoginStepUserInputUserInput),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    LoginStepUserInput object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LoginStepUserInputBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(LoginStepUserInputTypeEnum),
          ) as LoginStepUserInputTypeEnum;
          result.type = valueDes;
          break;
        case r'user_input':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(LoginStepUserInputUserInput),
          ) as LoginStepUserInputUserInput;
          result.userInput.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LoginStepUserInput deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LoginStepUserInputBuilder();
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

class LoginStepUserInputTypeEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'user_input')
  static const LoginStepUserInputTypeEnum userInput = _$loginStepUserInputTypeEnum_userInput;

  static Serializer<LoginStepUserInputTypeEnum> get serializer => _$loginStepUserInputTypeEnumSerializer;

  const LoginStepUserInputTypeEnum._(String name): super(name);

  static BuiltSet<LoginStepUserInputTypeEnum> get values => _$loginStepUserInputTypeEnumValues;
  static LoginStepUserInputTypeEnum valueOf(String name) => _$loginStepUserInputTypeEnumValueOf(name);
}

