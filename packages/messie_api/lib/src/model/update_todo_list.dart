//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'update_todo_list.g.dart';

/// UpdateTodoList
///
/// Properties:
/// * [title] 
/// * [description] 
@BuiltValue()
abstract class UpdateTodoList implements Built<UpdateTodoList, UpdateTodoListBuilder> {
  @BuiltValueField(wireName: r'title')
  String get title;

  @BuiltValueField(wireName: r'description')
  String get description;

  UpdateTodoList._();

  factory UpdateTodoList([void updates(UpdateTodoListBuilder b)]) = _$UpdateTodoList;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpdateTodoListBuilder b) => b
      ..title = '';

  @BuiltValueSerializer(custom: true)
  static Serializer<UpdateTodoList> get serializer => _$UpdateTodoListSerializer();
}

class _$UpdateTodoListSerializer implements PrimitiveSerializer<UpdateTodoList> {
  @override
  final Iterable<Type> types = const [UpdateTodoList, _$UpdateTodoList];

  @override
  final String wireName = r'UpdateTodoList';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpdateTodoList object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'title';
    yield serializers.serialize(
      object.title,
      specifiedType: const FullType(String),
    );
    yield r'description';
    yield serializers.serialize(
      object.description,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    UpdateTodoList object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UpdateTodoListBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.title = valueDes;
          break;
        case r'description':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.description = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UpdateTodoList deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpdateTodoListBuilder();
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

