//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:messie_api/src/model/email_message_header.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'email_messages_response.g.dart';

/// EmailMessagesResponse
///
/// Properties:
/// * [messages] 
/// * [unreadCount] 
@BuiltValue()
abstract class EmailMessagesResponse implements Built<EmailMessagesResponse, EmailMessagesResponseBuilder> {
  @BuiltValueField(wireName: r'messages')
  BuiltList<EmailMessageHeader>? get messages;

  @BuiltValueField(wireName: r'unreadCount')
  int? get unreadCount;

  EmailMessagesResponse._();

  factory EmailMessagesResponse([void updates(EmailMessagesResponseBuilder b)]) = _$EmailMessagesResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EmailMessagesResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EmailMessagesResponse> get serializer => _$EmailMessagesResponseSerializer();
}

class _$EmailMessagesResponseSerializer implements PrimitiveSerializer<EmailMessagesResponse> {
  @override
  final Iterable<Type> types = const [EmailMessagesResponse, _$EmailMessagesResponse];

  @override
  final String wireName = r'EmailMessagesResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EmailMessagesResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.messages != null) {
      yield r'messages';
      yield serializers.serialize(
        object.messages,
        specifiedType: const FullType(BuiltList, [FullType(EmailMessageHeader)]),
      );
    }
    if (object.unreadCount != null) {
      yield r'unreadCount';
      yield serializers.serialize(
        object.unreadCount,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    EmailMessagesResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EmailMessagesResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'messages':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(EmailMessageHeader)]),
          ) as BuiltList<EmailMessageHeader>;
          result.messages.replace(valueDes);
          break;
        case r'unreadCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.unreadCount = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EmailMessagesResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EmailMessagesResponseBuilder();
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

