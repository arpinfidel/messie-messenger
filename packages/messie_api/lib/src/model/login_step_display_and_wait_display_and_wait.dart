//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'login_step_display_and_wait_display_and_wait.g.dart';

/// LoginStepDisplayAndWaitDisplayAndWait
///
/// Properties:
/// * [message] 
/// * [data] 
/// * [imageUrl] 
@BuiltValue()
abstract class LoginStepDisplayAndWaitDisplayAndWait implements Built<LoginStepDisplayAndWaitDisplayAndWait, LoginStepDisplayAndWaitDisplayAndWaitBuilder> {
  @BuiltValueField(wireName: r'message')
  String? get message;

  @BuiltValueField(wireName: r'data')
  String? get data;

  @BuiltValueField(wireName: r'image_url')
  String? get imageUrl;

  LoginStepDisplayAndWaitDisplayAndWait._();

  factory LoginStepDisplayAndWaitDisplayAndWait([void updates(LoginStepDisplayAndWaitDisplayAndWaitBuilder b)]) = _$LoginStepDisplayAndWaitDisplayAndWait;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LoginStepDisplayAndWaitDisplayAndWaitBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LoginStepDisplayAndWaitDisplayAndWait> get serializer => _$LoginStepDisplayAndWaitDisplayAndWaitSerializer();
}

class _$LoginStepDisplayAndWaitDisplayAndWaitSerializer implements PrimitiveSerializer<LoginStepDisplayAndWaitDisplayAndWait> {
  @override
  final Iterable<Type> types = const [LoginStepDisplayAndWaitDisplayAndWait, _$LoginStepDisplayAndWaitDisplayAndWait];

  @override
  final String wireName = r'LoginStepDisplayAndWaitDisplayAndWait';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LoginStepDisplayAndWaitDisplayAndWait object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.message != null) {
      yield r'message';
      yield serializers.serialize(
        object.message,
        specifiedType: const FullType(String),
      );
    }
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(String),
      );
    }
    if (object.imageUrl != null) {
      yield r'image_url';
      yield serializers.serialize(
        object.imageUrl,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    LoginStepDisplayAndWaitDisplayAndWait object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LoginStepDisplayAndWaitDisplayAndWaitBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'message':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.message = valueDes;
          break;
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.data = valueDes;
          break;
        case r'image_url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.imageUrl = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LoginStepDisplayAndWaitDisplayAndWait deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LoginStepDisplayAndWaitDisplayAndWaitBuilder();
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

