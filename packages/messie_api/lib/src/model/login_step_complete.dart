//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:messie_api/src/model/login_step_complete_complete.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'login_step_complete.g.dart';

/// LoginStepComplete
///
/// Properties:
/// * [type] 
/// * [complete] 
@BuiltValue()
abstract class LoginStepComplete implements Built<LoginStepComplete, LoginStepCompleteBuilder> {
  @BuiltValueField(wireName: r'type')
  LoginStepCompleteTypeEnum get type;
  // enum typeEnum {  complete,  };

  @BuiltValueField(wireName: r'complete')
  LoginStepCompleteComplete get complete;

  LoginStepComplete._();

  factory LoginStepComplete([void updates(LoginStepCompleteBuilder b)]) = _$LoginStepComplete;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LoginStepCompleteBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LoginStepComplete> get serializer => _$LoginStepCompleteSerializer();
}

class _$LoginStepCompleteSerializer implements PrimitiveSerializer<LoginStepComplete> {
  @override
  final Iterable<Type> types = const [LoginStepComplete, _$LoginStepComplete];

  @override
  final String wireName = r'LoginStepComplete';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LoginStepComplete object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'type';
    yield serializers.serialize(
      object.type,
      specifiedType: const FullType(LoginStepCompleteTypeEnum),
    );
    yield r'complete';
    yield serializers.serialize(
      object.complete,
      specifiedType: const FullType(LoginStepCompleteComplete),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    LoginStepComplete object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LoginStepCompleteBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(LoginStepCompleteTypeEnum),
          ) as LoginStepCompleteTypeEnum;
          result.type = valueDes;
          break;
        case r'complete':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(LoginStepCompleteComplete),
          ) as LoginStepCompleteComplete;
          result.complete.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LoginStepComplete deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LoginStepCompleteBuilder();
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

class LoginStepCompleteTypeEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'complete')
  static const LoginStepCompleteTypeEnum complete = _$loginStepCompleteTypeEnum_complete;

  static Serializer<LoginStepCompleteTypeEnum> get serializer => _$loginStepCompleteTypeEnumSerializer;

  const LoginStepCompleteTypeEnum._(String name): super(name);

  static BuiltSet<LoginStepCompleteTypeEnum> get values => _$loginStepCompleteTypeEnumValues;
  static LoginStepCompleteTypeEnum valueOf(String name) => _$loginStepCompleteTypeEnumValueOf(name);
}

