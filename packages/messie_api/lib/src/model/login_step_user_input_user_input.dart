//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:messie_api/src/model/login_step_user_input_user_input_fields_inner.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'login_step_user_input_user_input.g.dart';

/// LoginStepUserInputUserInput
///
/// Properties:
/// * [fields] 
@BuiltValue()
abstract class LoginStepUserInputUserInput implements Built<LoginStepUserInputUserInput, LoginStepUserInputUserInputBuilder> {
  @BuiltValueField(wireName: r'fields')
  BuiltList<LoginStepUserInputUserInputFieldsInner>? get fields;

  LoginStepUserInputUserInput._();

  factory LoginStepUserInputUserInput([void updates(LoginStepUserInputUserInputBuilder b)]) = _$LoginStepUserInputUserInput;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LoginStepUserInputUserInputBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LoginStepUserInputUserInput> get serializer => _$LoginStepUserInputUserInputSerializer();
}

class _$LoginStepUserInputUserInputSerializer implements PrimitiveSerializer<LoginStepUserInputUserInput> {
  @override
  final Iterable<Type> types = const [LoginStepUserInputUserInput, _$LoginStepUserInputUserInput];

  @override
  final String wireName = r'LoginStepUserInputUserInput';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LoginStepUserInputUserInput object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.fields != null) {
      yield r'fields';
      yield serializers.serialize(
        object.fields,
        specifiedType: const FullType(BuiltList, [FullType(LoginStepUserInputUserInputFieldsInner)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    LoginStepUserInputUserInput object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LoginStepUserInputUserInputBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'fields':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(LoginStepUserInputUserInputFieldsInner)]),
          ) as BuiltList<LoginStepUserInputUserInputFieldsInner>;
          result.fields.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LoginStepUserInputUserInput deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LoginStepUserInputUserInputBuilder();
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

