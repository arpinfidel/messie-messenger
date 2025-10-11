//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'email_login_request.g.dart';

/// EmailLoginRequest
///
/// Properties:
/// * [host] 
/// * [port] 
/// * [email] 
/// * [appPassword] 
@BuiltValue(instantiable: false)
abstract class EmailLoginRequest  {
  @BuiltValueField(wireName: r'host')
  String get host;

  @BuiltValueField(wireName: r'port')
  int get port;

  @BuiltValueField(wireName: r'email')
  String get email;

  @BuiltValueField(wireName: r'appPassword')
  String get appPassword;

  @BuiltValueSerializer(custom: true)
  static Serializer<EmailLoginRequest> get serializer => _$EmailLoginRequestSerializer();
}

class _$EmailLoginRequestSerializer implements PrimitiveSerializer<EmailLoginRequest> {
  @override
  final Iterable<Type> types = const [EmailLoginRequest];

  @override
  final String wireName = r'EmailLoginRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EmailLoginRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'host';
    yield serializers.serialize(
      object.host,
      specifiedType: const FullType(String),
    );
    yield r'port';
    yield serializers.serialize(
      object.port,
      specifiedType: const FullType(int),
    );
    yield r'email';
    yield serializers.serialize(
      object.email,
      specifiedType: const FullType(String),
    );
    yield r'appPassword';
    yield serializers.serialize(
      object.appPassword,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    EmailLoginRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  @override
  EmailLoginRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.deserialize(serialized, specifiedType: FullType($EmailLoginRequest)) as $EmailLoginRequest;
  }
}

/// a concrete implementation of [EmailLoginRequest], since [EmailLoginRequest] is not instantiable
@BuiltValue(instantiable: true)
abstract class $EmailLoginRequest implements EmailLoginRequest, Built<$EmailLoginRequest, $EmailLoginRequestBuilder> {
  $EmailLoginRequest._();

  factory $EmailLoginRequest([void Function($EmailLoginRequestBuilder)? updates]) = _$$EmailLoginRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults($EmailLoginRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<$EmailLoginRequest> get serializer => _$$EmailLoginRequestSerializer();
}

class _$$EmailLoginRequestSerializer implements PrimitiveSerializer<$EmailLoginRequest> {
  @override
  final Iterable<Type> types = const [$EmailLoginRequest, _$$EmailLoginRequest];

  @override
  final String wireName = r'$EmailLoginRequest';

  @override
  Object serialize(
    Serializers serializers,
    $EmailLoginRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.serialize(object, specifiedType: FullType(EmailLoginRequest))!;
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EmailLoginRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'host':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.host = valueDes;
          break;
        case r'port':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.port = valueDes;
          break;
        case r'email':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.email = valueDes;
          break;
        case r'appPassword':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.appPassword = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  $EmailLoginRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = $EmailLoginRequestBuilder();
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

