//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'matrix_auth_response.g.dart';

/// MatrixAuthResponse
///
/// Properties:
/// * [token] - JWT token for authentication
/// * [mxid] - Matrix user ID
/// * [userId] - ID of the user in the todo service
@BuiltValue()
abstract class MatrixAuthResponse implements Built<MatrixAuthResponse, MatrixAuthResponseBuilder> {
  /// JWT token for authentication
  @BuiltValueField(wireName: r'token')
  String get token;

  /// Matrix user ID
  @BuiltValueField(wireName: r'mxid')
  String get mxid;

  /// ID of the user in the todo service
  @BuiltValueField(wireName: r'user_id')
  String get userId;

  MatrixAuthResponse._();

  factory MatrixAuthResponse([void updates(MatrixAuthResponseBuilder b)]) = _$MatrixAuthResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MatrixAuthResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MatrixAuthResponse> get serializer => _$MatrixAuthResponseSerializer();
}

class _$MatrixAuthResponseSerializer implements PrimitiveSerializer<MatrixAuthResponse> {
  @override
  final Iterable<Type> types = const [MatrixAuthResponse, _$MatrixAuthResponse];

  @override
  final String wireName = r'MatrixAuthResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MatrixAuthResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'token';
    yield serializers.serialize(
      object.token,
      specifiedType: const FullType(String),
    );
    yield r'mxid';
    yield serializers.serialize(
      object.mxid,
      specifiedType: const FullType(String),
    );
    yield r'user_id';
    yield serializers.serialize(
      object.userId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    MatrixAuthResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MatrixAuthResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'token':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.token = valueDes;
          break;
        case r'mxid':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.mxid = valueDes;
          break;
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
  MatrixAuthResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MatrixAuthResponseBuilder();
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

