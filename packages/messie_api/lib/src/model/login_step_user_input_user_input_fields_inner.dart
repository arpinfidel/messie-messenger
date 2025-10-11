//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'login_step_user_input_user_input_fields_inner.g.dart';

/// LoginStepUserInputUserInputFieldsInner
///
/// Properties:
/// * [id] 
/// * [label] 
/// * [kind] 
/// * [secret] 
@BuiltValue()
abstract class LoginStepUserInputUserInputFieldsInner implements Built<LoginStepUserInputUserInputFieldsInner, LoginStepUserInputUserInputFieldsInnerBuilder> {
  @BuiltValueField(wireName: r'id')
  String? get id;

  @BuiltValueField(wireName: r'label')
  String? get label;

  @BuiltValueField(wireName: r'kind')
  String? get kind;

  @BuiltValueField(wireName: r'secret')
  bool? get secret;

  LoginStepUserInputUserInputFieldsInner._();

  factory LoginStepUserInputUserInputFieldsInner([void updates(LoginStepUserInputUserInputFieldsInnerBuilder b)]) = _$LoginStepUserInputUserInputFieldsInner;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LoginStepUserInputUserInputFieldsInnerBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LoginStepUserInputUserInputFieldsInner> get serializer => _$LoginStepUserInputUserInputFieldsInnerSerializer();
}

class _$LoginStepUserInputUserInputFieldsInnerSerializer implements PrimitiveSerializer<LoginStepUserInputUserInputFieldsInner> {
  @override
  final Iterable<Type> types = const [LoginStepUserInputUserInputFieldsInner, _$LoginStepUserInputUserInputFieldsInner];

  @override
  final String wireName = r'LoginStepUserInputUserInputFieldsInner';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LoginStepUserInputUserInputFieldsInner object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.id != null) {
      yield r'id';
      yield serializers.serialize(
        object.id,
        specifiedType: const FullType(String),
      );
    }
    if (object.label != null) {
      yield r'label';
      yield serializers.serialize(
        object.label,
        specifiedType: const FullType(String),
      );
    }
    if (object.kind != null) {
      yield r'kind';
      yield serializers.serialize(
        object.kind,
        specifiedType: const FullType(String),
      );
    }
    if (object.secret != null) {
      yield r'secret';
      yield serializers.serialize(
        object.secret,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    LoginStepUserInputUserInputFieldsInner object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required LoginStepUserInputUserInputFieldsInnerBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'label':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.label = valueDes;
          break;
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.kind = valueDes;
          break;
        case r'secret':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.secret = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LoginStepUserInputUserInputFieldsInner deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LoginStepUserInputUserInputFieldsInnerBuilder();
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

