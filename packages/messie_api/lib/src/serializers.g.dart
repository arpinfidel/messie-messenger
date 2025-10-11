// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'serializers.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

Serializers _$serializers = (Serializers().toBuilder()
      ..add($EmailLoginRequest.serializer)
      ..add(AuthResponse.serializer)
      ..add(BridgeConnection.serializer)
      ..add(BridgeConnectionAccount.serializer)
      ..add(BridgeConnectionStatusEnum.serializer)
      ..add(CollaboratorDetail.serializer)
      ..add(EmailListRequest.serializer)
      ..add(EmailMessageHeader.serializer)
      ..add(EmailMessagesResponse.serializer)
      ..add(EmailRichHeader.serializer)
      ..add(EmailRichHeadersResponse.serializer)
      ..add(Error.serializer)
      ..add(LoginRequest.serializer)
      ..add(MatrixAuthResponse.serializer)
      ..add(MatrixOpenIDRequest.serializer)
      ..add(NewCollaborator.serializer)
      ..add(NewTodoItem.serializer)
      ..add(NewTodoList.serializer)
      ..add(RegisterRequest.serializer)
      ..add(TodoItem.serializer)
      ..add(TodoList.serializer)
      ..add(UpdateTodoItem.serializer)
      ..add(UpdateTodoList.serializer)
      ..add(User.serializer)
      ..add(WAStartResponse.serializer)
      ..add(WAStartResponseMethodEnum.serializer)
      ..add(WAStatusResponse.serializer)
      ..add(WAStatusResponseAccount.serializer)
      ..add(WAStatusResponseStateEnum.serializer)
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(EmailMessageHeader)]),
          () => ListBuilder<EmailMessageHeader>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(EmailRichHeader)]),
          () => ListBuilder<EmailRichHeader>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(String)]),
          () => ListBuilder<String>())
      ..addBuilderFactory(
          const FullType(BuiltList, const [const FullType(String)]),
          () => ListBuilder<String>())
      ..addBuilderFactory(
          const FullType(BuiltMap, const [
            const FullType(String),
            const FullType.nullable(JsonObject)
          ]),
          () => MapBuilder<String, JsonObject?>()))
    .build();

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
