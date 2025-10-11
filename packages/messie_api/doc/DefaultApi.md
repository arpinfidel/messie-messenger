# messie_api.api.DefaultApi

## Load the API package
```dart
import 'package:messie_api/api.dart';
```

All URIs are relative to *http://localhost:8080/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**addCollaborator**](DefaultApi.md#addcollaborator) | **POST** /todolists/{listId}/collaborators | Add a collaborator to a todo list
[**bridgeGetLoginFlows**](DefaultApi.md#bridgegetloginflows) | **GET** /bridge/provision/v3/login/flows | Get available login flows for a provider
[**bridgeLogout**](DefaultApi.md#bridgelogout) | **POST** /bridge/provision/v3/logout/{login_id} | Log out a specific login or all
[**bridgeStartLogin**](DefaultApi.md#bridgestartlogin) | **POST** /bridge/provision/v3/login/start/{flow} | Start a login process for a provider
[**bridgeSubmitLoginStep**](DefaultApi.md#bridgesubmitloginstep) | **POST** /bridge/provision/v3/login/step/{process_id}/{step_id}/{action} | Submit a login step
[**bridgeWhoami**](DefaultApi.md#bridgewhoami) | **GET** /bridge/provision/v3/whoami | Get provider-specific whoami with logins
[**createTodoItem**](DefaultApi.md#createtodoitem) | **POST** /todolists/{listId}/items | Create a new todo item in a list
[**createTodoList**](DefaultApi.md#createtodolist) | **POST** /todolists | Create a new todo list
[**deleteTodoItem**](DefaultApi.md#deletetodoitem) | **DELETE** /todolists/{listId}/items/{itemId} | Delete a todo item
[**deleteTodoList**](DefaultApi.md#deletetodolist) | **DELETE** /todolists/{listId} | Delete a todo list
[**emailHeaders**](DefaultApi.md#emailheaders) | **POST** /email/headers | List recent email headers with threading metadata
[**emailImportant**](DefaultApi.md#emailimportant) | **POST** /email/important | List recent important message headers (deprecated)
[**emailInbox**](DefaultApi.md#emailinbox) | **POST** /email/inbox | List recent inbox message headers
[**emailList**](DefaultApi.md#emaillist) | **POST** /email/list | List recent message headers for a mailbox or flag query
[**emailLoginTest**](DefaultApi.md#emaillogintest) | **POST** /email/login-test | Test email login and fetch recent message headers
[**emailThreads**](DefaultApi.md#emailthreads) | **POST** /email/threads | List recent email threads
[**getCollaborators**](DefaultApi.md#getcollaborators) | **GET** /todolists/{listId}/collaborators | Get collaborators for a todo list
[**getConnections**](DefaultApi.md#getconnections) | **GET** /connections | List bridge connections for current user
[**getTodoItemById**](DefaultApi.md#gettodoitembyid) | **GET** /todolists/{listId}/items/{itemId} | Get a todo item by ID
[**getTodoItemsByListId**](DefaultApi.md#gettodoitemsbylistid) | **GET** /todolists/{listId}/items | Get todo items by list ID
[**getTodoListById**](DefaultApi.md#gettodolistbyid) | **GET** /todolists/{listId} | Get a todo list by ID
[**getTodoListsByUserId**](DefaultApi.md#gettodolistsbyuserid) | **GET** /todolists | Get todo lists by owner ID
[**loginPost**](DefaultApi.md#loginpost) | **POST** /login | Log in a user
[**postMatrixAuth**](DefaultApi.md#postmatrixauth) | **POST** /auth/matrix/openid | Authenticate using Matrix OpenID
[**registerPost**](DefaultApi.md#registerpost) | **POST** /register | Register a new user
[**removeCollaborator**](DefaultApi.md#removecollaborator) | **DELETE** /todolists/{listId}/collaborators/{userId} | Remove a collaborator from a todo list
[**updateTodoItem**](DefaultApi.md#updatetodoitem) | **PUT** /todolists/{listId}/items/{itemId} | Update a todo item
[**updateTodoList**](DefaultApi.md#updatetodolist) | **PUT** /todolists/{listId} | Update a todo list
[**usersIdGet**](DefaultApi.md#usersidget) | **GET** /users/{id} | Get user by ID
[**usersMeGet**](DefaultApi.md#usersmeget) | **GET** /users/me | Get current user profile


# **addCollaborator**
> addCollaborator(listId, newCollaborator)

Add a collaborator to a todo list

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final String listId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | ID of the todo list
final NewCollaborator newCollaborator = ; // NewCollaborator | 

try {
    api.addCollaborator(listId, newCollaborator);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->addCollaborator: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **listId** | **String**| ID of the todo list | 
 **newCollaborator** | [**NewCollaborator**](NewCollaborator.md)|  | 

### Return type

void (empty response body)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **bridgeGetLoginFlows**
> BridgeLoginFlowsResponse bridgeGetLoginFlows(provider)

Get available login flows for a provider

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final String provider = whatsapp; // String | 

try {
    final response = api.bridgeGetLoginFlows(provider);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->bridgeGetLoginFlows: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **provider** | **String**|  | 

### Return type

[**BridgeLoginFlowsResponse**](BridgeLoginFlowsResponse.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **bridgeLogout**
> bridgeLogout(loginId, provider)

Log out a specific login or all

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final String loginId = all; // String | 
final String provider = whatsapp; // String | 

try {
    api.bridgeLogout(loginId, provider);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->bridgeLogout: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **loginId** | **String**|  | 
 **provider** | **String**|  | 

### Return type

void (empty response body)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **bridgeStartLogin**
> BridgeLoginStep bridgeStartLogin(flow, provider)

Start a login process for a provider

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final String flow = qr; // String | 
final String provider = whatsapp; // String | 

try {
    final response = api.bridgeStartLogin(flow, provider);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->bridgeStartLogin: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **flow** | **String**|  | 
 **provider** | **String**|  | 

### Return type

[**BridgeLoginStep**](BridgeLoginStep.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **bridgeSubmitLoginStep**
> BridgeLoginStep bridgeSubmitLoginStep(processId, stepId, action, provider, requestBody)

Submit a login step

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final String processId = processId_example; // String | 
final String stepId = stepId_example; // String | 
final String action = action_example; // String | 
final String provider = whatsapp; // String | 
final BuiltMap<String, JsonObject> requestBody = Object; // BuiltMap<String, JsonObject> | 

try {
    final response = api.bridgeSubmitLoginStep(processId, stepId, action, provider, requestBody);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->bridgeSubmitLoginStep: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **processId** | **String**|  | 
 **stepId** | **String**|  | 
 **action** | **String**|  | 
 **provider** | **String**|  | 
 **requestBody** | [**BuiltMap&lt;String, JsonObject&gt;**](JsonObject.md)|  | [optional] 

### Return type

[**BridgeLoginStep**](BridgeLoginStep.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **bridgeWhoami**
> BridgeWhoamiResponse bridgeWhoami(provider)

Get provider-specific whoami with logins

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final String provider = whatsapp; // String | 

try {
    final response = api.bridgeWhoami(provider);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->bridgeWhoami: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **provider** | **String**|  | 

### Return type

[**BridgeWhoamiResponse**](BridgeWhoamiResponse.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **createTodoItem**
> TodoItem createTodoItem(listId, newTodoItem)

Create a new todo item in a list

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final String listId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | ID of the todo list
final NewTodoItem newTodoItem = ; // NewTodoItem | 

try {
    final response = api.createTodoItem(listId, newTodoItem);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->createTodoItem: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **listId** | **String**| ID of the todo list | 
 **newTodoItem** | [**NewTodoItem**](NewTodoItem.md)|  | 

### Return type

[**TodoItem**](TodoItem.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **createTodoList**
> TodoList createTodoList(newTodoList)

Create a new todo list

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final NewTodoList newTodoList = ; // NewTodoList | 

try {
    final response = api.createTodoList(newTodoList);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->createTodoList: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **newTodoList** | [**NewTodoList**](NewTodoList.md)|  | 

### Return type

[**TodoList**](TodoList.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteTodoItem**
> deleteTodoItem(listId, itemId)

Delete a todo item

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final String listId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | ID of the todo list
final String itemId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | ID of the todo item to delete

try {
    api.deleteTodoItem(listId, itemId);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->deleteTodoItem: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **listId** | **String**| ID of the todo list | 
 **itemId** | **String**| ID of the todo item to delete | 

### Return type

void (empty response body)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteTodoList**
> deleteTodoList(listId)

Delete a todo list

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final String listId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | ID of the todo list to delete

try {
    api.deleteTodoList(listId);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->deleteTodoList: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **listId** | **String**| ID of the todo list to delete | 

### Return type

void (empty response body)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **emailHeaders**
> EmailRichHeadersResponse emailHeaders(emailLoginRequest)

List recent email headers with threading metadata

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final EmailLoginRequest emailLoginRequest = ; // EmailLoginRequest | 

try {
    final response = api.emailHeaders(emailLoginRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->emailHeaders: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **emailLoginRequest** | [**EmailLoginRequest**](EmailLoginRequest.md)|  | 

### Return type

[**EmailRichHeadersResponse**](EmailRichHeadersResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **emailImportant**
> emailImportant(emailLoginRequest)

List recent important message headers (deprecated)

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final EmailLoginRequest emailLoginRequest = ; // EmailLoginRequest | 

try {
    api.emailImportant(emailLoginRequest);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->emailImportant: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **emailLoginRequest** | [**EmailLoginRequest**](EmailLoginRequest.md)|  | 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **emailInbox**
> EmailMessagesResponse emailInbox(emailLoginRequest)

List recent inbox message headers

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final EmailLoginRequest emailLoginRequest = ; // EmailLoginRequest | 

try {
    final response = api.emailInbox(emailLoginRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->emailInbox: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **emailLoginRequest** | [**EmailLoginRequest**](EmailLoginRequest.md)|  | 

### Return type

[**EmailMessagesResponse**](EmailMessagesResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **emailList**
> EmailMessagesResponse emailList(emailListRequest)

List recent message headers for a mailbox or flag query

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final EmailListRequest emailListRequest = ; // EmailListRequest | 

try {
    final response = api.emailList(emailListRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->emailList: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **emailListRequest** | [**EmailListRequest**](EmailListRequest.md)|  | 

### Return type

[**EmailMessagesResponse**](EmailMessagesResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **emailLoginTest**
> EmailMessagesResponse emailLoginTest(emailLoginRequest)

Test email login and fetch recent message headers

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final EmailLoginRequest emailLoginRequest = ; // EmailLoginRequest | 

try {
    final response = api.emailLoginTest(emailLoginRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->emailLoginTest: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **emailLoginRequest** | [**EmailLoginRequest**](EmailLoginRequest.md)|  | 

### Return type

[**EmailMessagesResponse**](EmailMessagesResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **emailThreads**
> EmailMessagesResponse emailThreads(emailLoginRequest)

List recent email threads

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final EmailLoginRequest emailLoginRequest = ; // EmailLoginRequest | 

try {
    final response = api.emailThreads(emailLoginRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->emailThreads: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **emailLoginRequest** | [**EmailLoginRequest**](EmailLoginRequest.md)|  | 

### Return type

[**EmailMessagesResponse**](EmailMessagesResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getCollaborators**
> BuiltList<CollaboratorDetail> getCollaborators(listId)

Get collaborators for a todo list

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final String listId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | ID of the todo list to retrieve collaborators for

try {
    final response = api.getCollaborators(listId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->getCollaborators: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **listId** | **String**| ID of the todo list to retrieve collaborators for | 

### Return type

[**BuiltList&lt;CollaboratorDetail&gt;**](CollaboratorDetail.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getConnections**
> BuiltList<BridgeConnection> getConnections()

List bridge connections for current user

Returns zero or more connection entries per provider. Providers that support multi-account logins will return multiple items with the same `provider` value, one per account. 

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();

try {
    final response = api.getConnections();
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->getConnections: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**BuiltList&lt;BridgeConnection&gt;**](BridgeConnection.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getTodoItemById**
> TodoItem getTodoItemById(listId, itemId)

Get a todo item by ID

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final String listId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | ID of the todo list
final String itemId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | ID of the todo item to retrieve

try {
    final response = api.getTodoItemById(listId, itemId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->getTodoItemById: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **listId** | **String**| ID of the todo list | 
 **itemId** | **String**| ID of the todo item to retrieve | 

### Return type

[**TodoItem**](TodoItem.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getTodoItemsByListId**
> BuiltList<TodoItem> getTodoItemsByListId(listId)

Get todo items by list ID

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final String listId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | ID of the todo list to retrieve items for

try {
    final response = api.getTodoItemsByListId(listId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->getTodoItemsByListId: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **listId** | **String**| ID of the todo list to retrieve items for | 

### Return type

[**BuiltList&lt;TodoItem&gt;**](TodoItem.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getTodoListById**
> TodoList getTodoListById(listId)

Get a todo list by ID

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final String listId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | ID of the todo list to retrieve

try {
    final response = api.getTodoListById(listId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->getTodoListById: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **listId** | **String**| ID of the todo list to retrieve | 

### Return type

[**TodoList**](TodoList.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getTodoListsByUserId**
> BuiltList<TodoList> getTodoListsByUserId(userId)

Get todo lists by owner ID

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final String userId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | ID of the user to retrieve todo lists for

try {
    final response = api.getTodoListsByUserId(userId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->getTodoListsByUserId: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **userId** | **String**| ID of the user to retrieve todo lists for | 

### Return type

[**BuiltList&lt;TodoList&gt;**](TodoList.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **loginPost**
> AuthResponse loginPost(loginRequest)

Log in a user

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final LoginRequest loginRequest = ; // LoginRequest | 

try {
    final response = api.loginPost(loginRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->loginPost: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **loginRequest** | [**LoginRequest**](LoginRequest.md)|  | 

### Return type

[**AuthResponse**](AuthResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **postMatrixAuth**
> MatrixAuthResponse postMatrixAuth(matrixOpenIDRequest)

Authenticate using Matrix OpenID

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final MatrixOpenIDRequest matrixOpenIDRequest = ; // MatrixOpenIDRequest | 

try {
    final response = api.postMatrixAuth(matrixOpenIDRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->postMatrixAuth: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **matrixOpenIDRequest** | [**MatrixOpenIDRequest**](MatrixOpenIDRequest.md)|  | 

### Return type

[**MatrixAuthResponse**](MatrixAuthResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **registerPost**
> AuthResponse registerPost(registerRequest)

Register a new user

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final RegisterRequest registerRequest = ; // RegisterRequest | 

try {
    final response = api.registerPost(registerRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->registerPost: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **registerRequest** | [**RegisterRequest**](RegisterRequest.md)|  | 

### Return type

[**AuthResponse**](AuthResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **removeCollaborator**
> removeCollaborator(listId, userId)

Remove a collaborator from a todo list

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final String listId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | ID of the todo list
final String userId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | ID of the user to remove as collaborator

try {
    api.removeCollaborator(listId, userId);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->removeCollaborator: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **listId** | **String**| ID of the todo list | 
 **userId** | **String**| ID of the user to remove as collaborator | 

### Return type

void (empty response body)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateTodoItem**
> TodoItem updateTodoItem(listId, itemId, updateTodoItem)

Update a todo item

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final String listId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | ID of the todo list
final String itemId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | ID of the todo item to update
final UpdateTodoItem updateTodoItem = ; // UpdateTodoItem | 

try {
    final response = api.updateTodoItem(listId, itemId, updateTodoItem);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->updateTodoItem: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **listId** | **String**| ID of the todo list | 
 **itemId** | **String**| ID of the todo item to update | 
 **updateTodoItem** | [**UpdateTodoItem**](UpdateTodoItem.md)|  | 

### Return type

[**TodoItem**](TodoItem.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateTodoList**
> TodoList updateTodoList(listId, updateTodoList)

Update a todo list

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final String listId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | ID of the todo list to update
final UpdateTodoList updateTodoList = ; // UpdateTodoList | 

try {
    final response = api.updateTodoList(listId, updateTodoList);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->updateTodoList: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **listId** | **String**| ID of the todo list to update | 
 **updateTodoList** | [**UpdateTodoList**](UpdateTodoList.md)|  | 

### Return type

[**TodoList**](TodoList.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **usersIdGet**
> User usersIdGet(id)

Get user by ID

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();
final String id = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | User ID

try {
    final response = api.usersIdGet(id);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->usersIdGet: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **String**| User ID | 

### Return type

[**User**](User.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **usersMeGet**
> User usersMeGet()

Get current user profile

### Example
```dart
import 'package:messie_api/api.dart';

final api = MessieApi().getDefaultApi();

try {
    final response = api.usersMeGet();
    print(response);
} catch on DioException (e) {
    print('Exception when calling DefaultApi->usersMeGet: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**User**](User.md)

### Authorization

[bearerAuth](../README.md#bearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

