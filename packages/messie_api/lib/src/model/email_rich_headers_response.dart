//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:messie_api/src/model/email_rich_header.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'email_rich_headers_response.g.dart';

/// EmailRichHeadersResponse
///
/// Properties:
/// * [messages] 
@BuiltValue()
abstract class EmailRichHeadersResponse implements Built<EmailRichHeadersResponse, EmailRichHeadersResponseBuilder> {
  @BuiltValueField(wireName: r'messages')
  BuiltList<EmailRichHeader> get messages;

  EmailRichHeadersResponse._();

  factory EmailRichHeadersResponse([void updates(EmailRichHeadersResponseBuilder b)]) = _$EmailRichHeadersResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EmailRichHeadersResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EmailRichHeadersResponse> get serializer => _$EmailRichHeadersResponseSerializer();
}

class _$EmailRichHeadersResponseSerializer implements PrimitiveSerializer<EmailRichHeadersResponse> {
  @override
  final Iterable<Type> types = const [EmailRichHeadersResponse, _$EmailRichHeadersResponse];

  @override
  final String wireName = r'EmailRichHeadersResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EmailRichHeadersResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'messages';
    yield serializers.serialize(
      object.messages,
      specifiedType: const FullType(BuiltList, [FullType(EmailRichHeader)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    EmailRichHeadersResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EmailRichHeadersResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'messages':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(EmailRichHeader)]),
          ) as BuiltList<EmailRichHeader>;
          result.messages.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EmailRichHeadersResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EmailRichHeadersResponseBuilder();
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

