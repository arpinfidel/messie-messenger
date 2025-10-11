//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'login_step_cookies_cookies.g.dart';

/// LoginStepCookiesCookies
///
/// Properties:
/// * [names] 
@BuiltValue()
abstract class LoginStepCookiesCookies implements Built<LoginStepCookiesCookies, LoginStepCookiesCookiesBuilder> {
  @BuiltValueField(wireName: r'names')
  BuiltList<String>? get names;

  LoginStepCookiesCookies._();

  factory LoginStepCookiesCookies([void updates(LoginStepCookiesCookiesBuilder b)]) = _$LoginStepCookiesCookies;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LoginStepCookiesCookiesBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LoginStepCookiesCookies> get serializer => _$LoginStepCookiesCookiesSerializer();
}

class _$LoginStepCookiesCookiesSerializer implements PrimitiveSerializer<LoginStepCookiesCookies> {
  @override
  final Iterable<Type> types = const [LoginStepCookiesCookies, _$LoginStepCookiesCookies];

  @override
  final String wireName = r'LoginStepCookiesCookies';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LoginStepCookiesCookies object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.names != null) {
      yield r'names';
      yield serializers.serialize(
        object.names,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    LoginStepCookiesCookies object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LoginStepCookiesCookiesBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'names':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.names.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LoginStepCookiesCookies deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LoginStepCookiesCookiesBuilder();
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

