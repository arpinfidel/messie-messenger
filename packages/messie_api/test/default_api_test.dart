import 'package:test/test.dart';
import 'package:messie_api/messie_api.dart';


/// tests for DefaultApi
void main() {
  final instance = MessieApi().getDefaultApi();

  group(DefaultApi, () {
    // Add a collaborator to a todo list
    //
    //Future addCollaborator(String listId, NewCollaborator newCollaborator) async
    test('test addCollaborator', () async {
      // TODO
    });

    // Create a new todo item in a list
    //
    //Future<TodoItem> createTodoItem(String listId, NewTodoItem newTodoItem) async
    test('test createTodoItem', () async {
      // TODO
    });

    // Create a new todo list
    //
    //Future<TodoList> createTodoList(NewTodoList newTodoList) async
    test('test createTodoList', () async {
      // TODO
    });

    // Delete a todo item
    //
    //Future deleteTodoItem(String listId, String itemId) async
    test('test deleteTodoItem', () async {
      // TODO
    });

    // Delete a todo list
    //
    //Future deleteTodoList(String listId) async
    test('test deleteTodoList', () async {
      // TODO
    });

    // List recent email headers with threading metadata
    //
    //Future<EmailRichHeadersResponse> emailHeaders(EmailLoginRequest emailLoginRequest) async
    test('test emailHeaders', () async {
      // TODO
    });

    // List recent important message headers (deprecated)
    //
    //Future emailImportant(EmailLoginRequest emailLoginRequest) async
    test('test emailImportant', () async {
      // TODO
    });

    // List recent inbox message headers
    //
    //Future<EmailMessagesResponse> emailInbox(EmailLoginRequest emailLoginRequest) async
    test('test emailInbox', () async {
      // TODO
    });

    // List recent message headers for a mailbox or flag query
    //
    //Future<EmailMessagesResponse> emailList(EmailListRequest emailListRequest) async
    test('test emailList', () async {
      // TODO
    });

    // Test email login and fetch recent message headers
    //
    //Future<EmailMessagesResponse> emailLoginTest(EmailLoginRequest emailLoginRequest) async
    test('test emailLoginTest', () async {
      // TODO
    });

    // List recent email threads
    //
    //Future<EmailMessagesResponse> emailThreads(EmailLoginRequest emailLoginRequest) async
    test('test emailThreads', () async {
      // TODO
    });

    // Get collaborators for a todo list
    //
    //Future<BuiltList<CollaboratorDetail>> getCollaborators(String listId) async
    test('test getCollaborators', () async {
      // TODO
    });

    // List bridge connections for current user
    //
    //Future<BuiltList<BridgeConnection>> getConnections() async
    test('test getConnections', () async {
      // TODO
    });

    // Get a todo item by ID
    //
    //Future<TodoItem> getTodoItemById(String listId, String itemId) async
    test('test getTodoItemById', () async {
      // TODO
    });

    // Get todo items by list ID
    //
    //Future<BuiltList<TodoItem>> getTodoItemsByListId(String listId) async
    test('test getTodoItemsByListId', () async {
      // TODO
    });

    // Get a todo list by ID
    //
    //Future<TodoList> getTodoListById(String listId) async
    test('test getTodoListById', () async {
      // TODO
    });

    // Get todo lists by owner ID
    //
    //Future<BuiltList<TodoList>> getTodoListsByUserId(String userId) async
    test('test getTodoListsByUserId', () async {
      // TODO
    });

    // Log in a user
    //
    //Future<AuthResponse> loginPost(LoginRequest loginRequest) async
    test('test loginPost', () async {
      // TODO
    });

    // Authenticate using Matrix OpenID
    //
    //Future<MatrixAuthResponse> postMatrixAuth(MatrixOpenIDRequest matrixOpenIDRequest) async
    test('test postMatrixAuth', () async {
      // TODO
    });

    // Register a new user
    //
    //Future<AuthResponse> registerPost(RegisterRequest registerRequest) async
    test('test registerPost', () async {
      // TODO
    });

    // Remove a collaborator from a todo list
    //
    //Future removeCollaborator(String listId, String userId) async
    test('test removeCollaborator', () async {
      // TODO
    });

    // Update a todo item
    //
    //Future<TodoItem> updateTodoItem(String listId, String itemId, UpdateTodoItem updateTodoItem) async
    test('test updateTodoItem', () async {
      // TODO
    });

    // Update a todo list
    //
    //Future<TodoList> updateTodoList(String listId, UpdateTodoList updateTodoList) async
    test('test updateTodoList', () async {
      // TODO
    });

    // Get user by ID
    //
    //Future<User> usersIdGet(String id) async
    test('test usersIdGet', () async {
      // TODO
    });

    // Get current user profile
    //
    //Future<User> usersMeGet() async
    test('test usersMeGet', () async {
      // TODO
    });

  });
}
