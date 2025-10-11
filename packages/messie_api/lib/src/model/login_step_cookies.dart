//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:messie_api/src/model/login_step_cookies_cookies.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'login_step_cookies.g.dart';

/// LoginStepCookies
///
/// Properties:
/// * [type] 
/// * [cookies] 
@BuiltValue()
abstract class LoginStepCookies implements Built<LoginStepCookies, LoginStepCookiesBuilder> {
  @BuiltValueField(wireName: r'type')
  LoginStepCookiesTypeEnum get type;
  // enum typeEnum {  cookies,  };

  @BuiltValueField(wireName: r'cookies')
  LoginStepCookiesCookies get cookies;

  LoginStepCookies._();

  factory LoginStepCookies([void updates(LoginStepCookiesBuilder b)]) = _$LoginStepCookies;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LoginStepCookiesBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LoginStepCookies> get serializer => _$LoginStepCookiesSerializer();
}

class _$LoginStepCookiesSerializer implements PrimitiveSerializer<LoginStepCookies> {
  @override
  final Iterable<Type> types = const [LoginStepCookies, _$LoginStepCookies];

  @override
  final String wireName = r'LoginStepCookies';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LoginStepCookies object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'type';
    yield serializers.serialize(
      object.type,
      specifiedType: const FullType(LoginStepCookiesTypeEnum),
    );
    yield r'cookies';
    yield serializers.serialize(
      object.cookies,
      specifiedType: const FullType(LoginStepCookiesCookies),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    LoginStepCookies object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LoginStepCookiesBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(LoginStepCookiesTypeEnum),
          ) as LoginStepCookiesTypeEnum;
          result.type = valueDes;
          break;
        case r'cookies':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(LoginStepCookiesCookies),
          ) as LoginStepCookiesCookies;
          result.cookies.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LoginStepCookies deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LoginStepCookiesBuilder();
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

class LoginStepCookiesTypeEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'cookies')
  static const LoginStepCookiesTypeEnum cookies = _$loginStepCookiesTypeEnum_cookies;

  static Serializer<LoginStepCookiesTypeEnum> get serializer => _$loginStepCookiesTypeEnumSerializer;

  const LoginStepCookiesTypeEnum._(String name): super(name);

  static BuiltSet<LoginStepCookiesTypeEnum> get values => _$loginStepCookiesTypeEnumValues;
  static LoginStepCookiesTypeEnum valueOf(String name) => _$loginStepCookiesTypeEnumValueOf(name);
}

