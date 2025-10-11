//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:messie_api/src/model/email_login_request.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'email_list_request.g.dart';

/// EmailListRequest
///
/// Properties:
/// * [host] 
/// * [port] 
/// * [email] 
/// * [appPassword] 
/// * [mailbox] - Mailbox name to select (defaults to INBOX when omitted)
/// * [searchFlags] - Optional IMAP flags to filter on (e.g. [\"\\\\Flagged\"])
@BuiltValue()
abstract class EmailListRequest implements EmailLoginRequest, Built<EmailListRequest, EmailListRequestBuilder> {
  /// Mailbox name to select (defaults to INBOX when omitted)
  @BuiltValueField(wireName: r'mailbox')
  String? get mailbox;

  /// Optional IMAP flags to filter on (e.g. [\"\\\\Flagged\"])
  @BuiltValueField(wireName: r'searchFlags')
  BuiltList<String>? get searchFlags;

  EmailListRequest._();

  factory EmailListRequest([void updates(EmailListRequestBuilder b)]) = _$EmailListRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EmailListRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EmailListRequest> get serializer => _$EmailListRequestSerializer();
}

class _$EmailListRequestSerializer implements PrimitiveSerializer<EmailListRequest> {
  @override
  final Iterable<Type> types = const [EmailListRequest, _$EmailListRequest];

  @override
  final String wireName = r'EmailListRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EmailListRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.searchFlags != null) {
      yield r'searchFlags';
      yield serializers.serialize(
        object.searchFlags,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    yield r'host';
    yield serializers.serialize(
      object.host,
      specifiedType: const FullType(String),
    );
    yield r'appPassword';
    yield serializers.serialize(
      object.appPassword,
      specifiedType: const FullType(String),
    );
    if (object.mailbox != null) {
      yield r'mailbox';
      yield serializers.serialize(
        object.mailbox,
        specifiedType: const FullType(String),
      );
    }
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
  }

  @override
  Object serialize(
    Serializers serializers,
    EmailListRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EmailListRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'searchFlags':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.searchFlags.replace(valueDes);
          break;
        case r'host':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.host = valueDes;
          break;
        case r'appPassword':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.appPassword = valueDes;
          break;
        case r'mailbox':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.mailbox = valueDes;
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EmailListRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EmailListRequestBuilder();
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

