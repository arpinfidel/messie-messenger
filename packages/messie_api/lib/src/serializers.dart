//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_import

import 'package:one_of_serializer/any_of_serializer.dart';
import 'package:one_of_serializer/one_of_serializer.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:built_value/standard_json_plugin.dart';
import 'package:built_value/iso_8601_date_time_serializer.dart';
import 'package:messie_api/src/date_serializer.dart';
import 'package:messie_api/src/model/date.dart';

import 'package:messie_api/src/model/auth_response.dart';
import 'package:messie_api/src/model/bridge_connection.dart';
import 'package:messie_api/src/model/bridge_connection_account.dart';
import 'package:messie_api/src/model/collaborator_detail.dart';
import 'package:messie_api/src/model/email_list_request.dart';
import 'package:messie_api/src/model/email_login_request.dart';
import 'package:messie_api/src/model/email_message_header.dart';
import 'package:messie_api/src/model/email_messages_response.dart';
import 'package:messie_api/src/model/email_rich_header.dart';
import 'package:messie_api/src/model/email_rich_headers_response.dart';
import 'package:messie_api/src/model/error.dart';
import 'package:messie_api/src/model/login_request.dart';
import 'package:messie_api/src/model/matrix_auth_response.dart';
import 'package:messie_api/src/model/matrix_open_id_request.dart';
import 'package:messie_api/src/model/new_collaborator.dart';
import 'package:messie_api/src/model/new_todo_item.dart';
import 'package:messie_api/src/model/new_todo_list.dart';
import 'package:messie_api/src/model/register_request.dart';
import 'package:messie_api/src/model/todo_item.dart';
import 'package:messie_api/src/model/todo_list.dart';
import 'package:messie_api/src/model/update_todo_item.dart';
import 'package:messie_api/src/model/update_todo_list.dart';
import 'package:messie_api/src/model/user.dart';
import 'package:messie_api/src/model/wa_start_response.dart';
import 'package:messie_api/src/model/wa_status_response.dart';
import 'package:messie_api/src/model/wa_status_response_account.dart';

part 'serializers.g.dart';

@SerializersFor([
  AuthResponse,
  BridgeConnection,
  BridgeConnectionAccount,
  CollaboratorDetail,
  EmailListRequest,
  EmailLoginRequest,$EmailLoginRequest,
  EmailMessageHeader,
  EmailMessagesResponse,
  EmailRichHeader,
  EmailRichHeadersResponse,
  Error,
  LoginRequest,
  MatrixAuthResponse,
  MatrixOpenIDRequest,
  NewCollaborator,
  NewTodoItem,
  NewTodoList,
  RegisterRequest,
  TodoItem,
  TodoList,
  UpdateTodoItem,
  UpdateTodoList,
  User,
  WAStartResponse,
  WAStatusResponse,
  WAStatusResponseAccount,
])
Serializers serializers = (_$serializers.toBuilder()
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(TodoItem)]),
        () => ListBuilder<TodoItem>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(TodoList)]),
        () => ListBuilder<TodoList>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(CollaboratorDetail)]),
        () => ListBuilder<CollaboratorDetail>(),
      )
      ..addBuilderFactory(
        const FullType(BuiltList, [FullType(BridgeConnection)]),
        () => ListBuilder<BridgeConnection>(),
      )
      ..add(EmailLoginRequest.serializer)
      ..add(const OneOfSerializer())
      ..add(const AnyOfSerializer())
      ..add(const DateSerializer())
      ..add(Iso8601DateTimeSerializer())
    ).build();

Serializers standardSerializers =
    (serializers.toBuilder()..addPlugin(StandardJsonPlugin())).build();
