import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'bridge/messie_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MessieApp()));
}

final pingProvider = FutureProvider<String>((ref) async {
  return rustPing();
});

class MessieApp extends StatelessWidget {
  const MessieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Messie',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
      ),
      home: const HomeScreen(),
    );
  }
}

class MatrixSession {
  const MatrixSession({
    required this.homeserverUrl,
    required this.userId,
    required this.accessToken,
    this.deviceId,
  });

  final String homeserverUrl;
  final String userId;
  final String accessToken;
  final String? deviceId;

  MatrixSession copyWith({
    String? accessToken,
    String? deviceId,
  }) {
    return MatrixSession(
      homeserverUrl: homeserverUrl,
      userId: userId,
      accessToken: accessToken ?? this.accessToken,
      deviceId: deviceId ?? this.deviceId,
    );
  }
}

class AuthException implements Exception {
  AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

const _kHomeserverKey = 'messie.homeserver';
const _kUserIdKey = 'messie.user_id';
const _kAccessTokenKey = 'messie.access_token';
const _kDeviceIdKey = 'messie.device_id';

final authControllerProvider =
    AsyncNotifierProvider<AuthController, MatrixSession?>(AuthController.new);

class AuthController extends AsyncNotifier<MatrixSession?> {
  late final FlutterSecureStorage _secureStorage;
  late final String _basePath;

  @override
  Future<MatrixSession?> build() async {
    _secureStorage = const FlutterSecureStorage();
    _basePath = await _resolveBasePath();
    return _loadExistingSession();
  }

  Future<void> login({
    required String homeserverUrl,
    required String username,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final result = await rustRestoreOrLogin(
        homeserverUrl: homeserverUrl.trim(),
        username: username.trim(),
        password: password,
        basePath: _basePath,
      );

      if (!result.isOk || result.data == null) {
        throw AuthException(result.error ?? 'Login failed');
      }

      final data = result.data!;
      final session = MatrixSession(
        homeserverUrl: data.homeserverUrl,
        userId: data.userId,
        accessToken: data.accessToken,
        deviceId: data.deviceId,
      );

      await _persistSession(session);
      return session;
    });
  }

  Future<void> logout() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final result = await rustLogout(basePath: _basePath);
      if (!result.isOk) {
        throw AuthException(result.error ?? 'Failed to log out');
      }
      await _clearStoredSession();
      return null;
    });
  }

  Future<MatrixSession?> _loadExistingSession() async {
    final homeserver = await _secureStorage.read(key: _kHomeserverKey);
    if (homeserver == null) {
      return null;
    }
    final userId = await _secureStorage.read(key: _kUserIdKey);
    final accessToken = await _secureStorage.read(key: _kAccessTokenKey);
    final deviceId = await _secureStorage.read(key: _kDeviceIdKey);

    if (userId == null || accessToken == null) {
      await _clearStoredSession();
      return null;
    }

    final result = await rustInitClient(
      homeserverUrl: homeserver,
      basePath: _basePath,
    );

    if (!result.isOk || result.data == null) {
      await _clearStoredSession();
      return null;
    }

    final data = result.data!;
    final session = MatrixSession(
      homeserverUrl: data.homeserverUrl,
      userId: data.userId,
      accessToken: accessToken,
      deviceId: data.deviceId ?? deviceId,
    );

    await _persistSession(session);
    return session;
  }

  Future<void> _persistSession(MatrixSession session) async {
    await _secureStorage.write(key: _kHomeserverKey, value: session.homeserverUrl);
    await _secureStorage.write(key: _kUserIdKey, value: session.userId);
    await _secureStorage.write(key: _kAccessTokenKey, value: session.accessToken);
    if (session.deviceId != null) {
      await _secureStorage.write(key: _kDeviceIdKey, value: session.deviceId);
    } else {
      await _secureStorage.delete(key: _kDeviceIdKey);
    }
  }

  Future<void> _clearStoredSession() async {
    await _secureStorage.delete(key: _kHomeserverKey);
    await _secureStorage.delete(key: _kUserIdKey);
    await _secureStorage.delete(key: _kAccessTokenKey);
    await _secureStorage.delete(key: _kDeviceIdKey);
  }

  Future<String> _resolveBasePath() async {
    final directory = await getApplicationSupportDirectory();
    final path = p.join(directory.path, 'messie', 'matrix');
    await Directory(path).create(recursive: true);
    return path;
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<MatrixSession?>>(authControllerProvider, (previous, next) {
      if (next.hasError) {
        final message = _errorMessage(next.error);
        if (message != null) {
          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger?.showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      }
    });

    final authState = ref.watch(authControllerProvider);

    if (authState.isLoading && !authState.hasValue && !authState.hasError) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final session = authState.valueOrNull;
    final errorText = authState.hasError ? _errorMessage(authState.error) : null;

    if (session != null) {
      return LoggedInView(session: session);
    }

    return LoginView(
      isProcessing: authState.isLoading,
      errorMessage: errorText,
    );
  }

  String? _errorMessage(Object? error) {
    if (error == null) {
      return null;
    }
    if (error is AuthException) {
      return error.message;
    }
    return error.toString();
  }
}

class LoginView extends ConsumerStatefulWidget {
  const LoginView({
    super.key,
    required this.isProcessing,
    this.errorMessage,
  });

  final bool isProcessing;
  final String? errorMessage;

  @override
  ConsumerState<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends ConsumerState<LoginView> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _homeserverController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _homeserverController = TextEditingController(text: 'https://matrix-client.matrix.org');
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _homeserverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messie Messenger'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Sign in to your Matrix account',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),
                    if (widget.errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          widget.errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    TextFormField(
                      controller: _homeserverController,
                      decoration: const InputDecoration(
                        labelText: 'Homeserver URL',
                        hintText: 'https://matrix-client.matrix.org',
                      ),
                      enabled: !widget.isProcessing,
                      keyboardType: TextInputType.url,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Homeserver URL is required';
                        }
                        final trimmed = value.trim();
                        if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
                          return 'Enter a valid URL starting with http or https';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username or user ID',
                        hintText: '@user:matrix.org',
                      ),
                      enabled: !widget.isProcessing,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Username is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                          onPressed: widget.isProcessing
                              ? null
                              : () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                        ),
                      ),
                      enabled: !widget.isProcessing,
                      obscureText: _obscurePassword,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Password is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: widget.isProcessing ? null : () => _submit(context),
                      icon: widget.isProcessing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_open),
                      label: Text(widget.isProcessing ? 'Signing in…' : 'Sign in'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    await ref.read(authControllerProvider.notifier).login(
          homeserverUrl: _homeserverController.text,
          username: _usernameController.text,
          password: _passwordController.text,
        );
  }
}

class LoggedInView extends ConsumerWidget {
  const LoggedInView({
    super.key,
    required this.session,
  });

  final MatrixSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pingState = ref.watch(pingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messie Messenger'),
        actions: [
          IconButton(
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome back, ${session.userId}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text('Homeserver: ${session.homeserverUrl}'),
            if (session.deviceId != null) Text('Device ID: ${session.deviceId}'),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Rust bridge status',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    pingState.when(
                      data: (value) => Text('Rust says: $value'),
                      loading: () => const Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('Calling Rust…'),
                        ],
                      ),
                      error: (error, _) => Text('Failed to call Rust: $error'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => ref.read(authControllerProvider.notifier).logout(),
              icon: const Icon(Icons.logout),
              label: const Text('Log out'),
            ),
          ],
        ),
      ),
    );
  }
}
