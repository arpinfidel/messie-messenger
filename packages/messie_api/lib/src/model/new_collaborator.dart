//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'new_collaborator.g.dart';

/// NewCollaborator
///
/// Properties:
/// * [userId] 
@BuiltValue()
abstract class NewCollaborator implements Built<NewCollaborator, NewCollaboratorBuilder> {
  @BuiltValueField(wireName: r'user_id')
  String get userId;

  NewCollaborator._();

  factory NewCollaborator([void updates(NewCollaboratorBuilder b)]) = _$NewCollaborator;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(NewCollaboratorBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<NewCollaborator> get serializer => _$NewCollaboratorSerializer();
}

class _$NewCollaboratorSerializer implements PrimitiveSerializer<NewCollaborator> {
  @override
  final Iterable<Type> types = const [NewCollaborator, _$NewCollaborator];

  @override
  final String wireName = r'NewCollaborator';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    NewCollaborator object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'user_id';
    yield serializers.serialize(
      object.userId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    NewCollaborator object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required NewCollaboratorBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'user_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.userId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  NewCollaborator deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = NewCollaboratorBuilder();
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

