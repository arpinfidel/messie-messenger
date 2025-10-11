//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'wa_status_response_account.g.dart';

/// WAStatusResponseAccount
///
/// Properties:
/// * [externalId] 
/// * [displayName] 
@BuiltValue()
abstract class WAStatusResponseAccount implements Built<WAStatusResponseAccount, WAStatusResponseAccountBuilder> {
  @BuiltValueField(wireName: r'externalId')
  String? get externalId;

  @BuiltValueField(wireName: r'displayName')
  String? get displayName;

  WAStatusResponseAccount._();

  factory WAStatusResponseAccount([void updates(WAStatusResponseAccountBuilder b)]) = _$WAStatusResponseAccount;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WAStatusResponseAccountBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WAStatusResponseAccount> get serializer => _$WAStatusResponseAccountSerializer();
}

class _$WAStatusResponseAccountSerializer implements PrimitiveSerializer<WAStatusResponseAccount> {
  @override
  final Iterable<Type> types = const [WAStatusResponseAccount, _$WAStatusResponseAccount];

  @override
  final String wireName = r'WAStatusResponseAccount';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WAStatusResponseAccount object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.externalId != null) {
      yield r'externalId';
      yield serializers.serialize(
        object.externalId,
        specifiedType: const FullType(String),
      );
    }
    if (object.displayName != null) {
      yield r'displayName';
      yield serializers.serialize(
        object.displayName,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    WAStatusResponseAccount object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required WAStatusResponseAccountBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'externalId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.externalId = valueDes;
          break;
        case r'displayName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.displayName = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  WAStatusResponseAccount deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WAStatusResponseAccountBuilder();
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

