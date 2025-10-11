//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'matrix_open_id_request.g.dart';

/// MatrixOpenIDRequest
///
/// Properties:
/// * [accessToken] - Matrix OpenID access token
/// * [matrixServerName] - Matrix homeserver name
@BuiltValue()
abstract class MatrixOpenIDRequest implements Built<MatrixOpenIDRequest, MatrixOpenIDRequestBuilder> {
  /// Matrix OpenID access token
  @BuiltValueField(wireName: r'access_token')
  String get accessToken;

  /// Matrix homeserver name
  @BuiltValueField(wireName: r'matrix_server_name')
  String get matrixServerName;

  MatrixOpenIDRequest._();

  factory MatrixOpenIDRequest([void updates(MatrixOpenIDRequestBuilder b)]) = _$MatrixOpenIDRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MatrixOpenIDRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MatrixOpenIDRequest> get serializer => _$MatrixOpenIDRequestSerializer();
}

class _$MatrixOpenIDRequestSerializer implements PrimitiveSerializer<MatrixOpenIDRequest> {
  @override
  final Iterable<Type> types = const [MatrixOpenIDRequest, _$MatrixOpenIDRequest];

  @override
  final String wireName = r'MatrixOpenIDRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MatrixOpenIDRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'access_token';
    yield serializers.serialize(
      object.accessToken,
      specifiedType: const FullType(String),
    );
    yield r'matrix_server_name';
    yield serializers.serialize(
      object.matrixServerName,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    MatrixOpenIDRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MatrixOpenIDRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'access_token':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.accessToken = valueDes;
          break;
        case r'matrix_server_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.matrixServerName = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MatrixOpenIDRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MatrixOpenIDRequestBuilder();
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

