//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'login_step_complete_complete.g.dart';

/// LoginStepCompleteComplete
///
/// Properties:
/// * [userLoginId] 
@BuiltValue()
abstract class LoginStepCompleteComplete implements Built<LoginStepCompleteComplete, LoginStepCompleteCompleteBuilder> {
  @BuiltValueField(wireName: r'user_login_id')
  String? get userLoginId;

  LoginStepCompleteComplete._();

  factory LoginStepCompleteComplete([void updates(LoginStepCompleteCompleteBuilder b)]) = _$LoginStepCompleteComplete;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LoginStepCompleteCompleteBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LoginStepCompleteComplete> get serializer => _$LoginStepCompleteCompleteSerializer();
}

class _$LoginStepCompleteCompleteSerializer implements PrimitiveSerializer<LoginStepCompleteComplete> {
  @override
  final Iterable<Type> types = const [LoginStepCompleteComplete, _$LoginStepCompleteComplete];

  @override
  final String wireName = r'LoginStepCompleteComplete';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LoginStepCompleteComplete object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.userLoginId != null) {
      yield r'user_login_id';
      yield serializers.serialize(
        object.userLoginId,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    LoginStepCompleteComplete object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LoginStepCompleteCompleteBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'user_login_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.userLoginId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LoginStepCompleteComplete deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LoginStepCompleteCompleteBuilder();
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

