//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'email_rich_header.g.dart';

/// EmailRichHeader
///
/// Properties:
/// * [from] 
/// * [subject] 
/// * [date] 
/// * [messageId] 
/// * [inReplyTo] 
/// * [references] 
@BuiltValue()
abstract class EmailRichHeader implements Built<EmailRichHeader, EmailRichHeaderBuilder> {
  @BuiltValueField(wireName: r'from')
  String? get from;

  @BuiltValueField(wireName: r'subject')
  String? get subject;

  @BuiltValueField(wireName: r'date')
  DateTime? get date;

  @BuiltValueField(wireName: r'messageId')
  String? get messageId;

  @BuiltValueField(wireName: r'inReplyTo')
  String? get inReplyTo;

  @BuiltValueField(wireName: r'references')
  BuiltList<String>? get references;

  EmailRichHeader._();

  factory EmailRichHeader([void updates(EmailRichHeaderBuilder b)]) = _$EmailRichHeader;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EmailRichHeaderBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EmailRichHeader> get serializer => _$EmailRichHeaderSerializer();
}

class _$EmailRichHeaderSerializer implements PrimitiveSerializer<EmailRichHeader> {
  @override
  final Iterable<Type> types = const [EmailRichHeader, _$EmailRichHeader];

  @override
  final String wireName = r'EmailRichHeader';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EmailRichHeader object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.from != null) {
      yield r'from';
      yield serializers.serialize(
        object.from,
        specifiedType: const FullType(String),
      );
    }
    if (object.subject != null) {
      yield r'subject';
      yield serializers.serialize(
        object.subject,
        specifiedType: const FullType(String),
      );
    }
    if (object.date != null) {
      yield r'date';
      yield serializers.serialize(
        object.date,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.messageId != null) {
      yield r'messageId';
      yield serializers.serialize(
        object.messageId,
        specifiedType: const FullType(String),
      );
    }
    if (object.inReplyTo != null) {
      yield r'inReplyTo';
      yield serializers.serialize(
        object.inReplyTo,
        specifiedType: const FullType(String),
      );
    }
    if (object.references != null) {
      yield r'references';
      yield serializers.serialize(
        object.references,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    EmailRichHeader object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EmailRichHeaderBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'from':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.from = valueDes;
          break;
        case r'subject':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.subject = valueDes;
          break;
        case r'date':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.date = valueDes;
          break;
        case r'messageId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.messageId = valueDes;
          break;
        case r'inReplyTo':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.inReplyTo = valueDes;
          break;
        case r'references':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.references.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EmailRichHeader deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EmailRichHeaderBuilder();
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

