import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'bridge/messie_bridge.dart';
import 'state/room_list_controller.dart';
import 'theme/app_theme.dart';
import 'theme/messie_tokens.dart';

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
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
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
    await _secureStorage.write(
        key: _kHomeserverKey, value: session.homeserverUrl);
    await _secureStorage.write(key: _kUserIdKey, value: session.userId);
    await _secureStorage.write(
        key: _kAccessTokenKey, value: session.accessToken);
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
    ref.listen<AsyncValue<MatrixSession?>>(authControllerProvider,
        (previous, next) {
      if (next.hasError) {
        final message = _errorMessage(next.error);
        if (message != null) {
          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger?.showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      }

      final session = next.asData?.value;
      final roomList = ref.read(roomListControllerProvider.notifier);
      if (session != null) {
        roomList.start();
      } else {
        roomList.stop();
      }
    });

    final authState = ref.watch(authControllerProvider);

    if (authState.isLoading && !authState.hasValue && !authState.hasError) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final session = authState.asData?.value;
    final errorText =
        authState.hasError ? _errorMessage(authState.error) : null;

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
    _homeserverController =
        TextEditingController(text: 'https://matrix-client.matrix.org');
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final spacing = MessieSpacing.of(context);
    final radii = MessieRadii.of(context);
    final surfaces = MessieSurfaces.of(context);
    final gutter = MessieSpacing.gutter(context);

    return Scaffold(
      body: SafeArea(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [surfaces.surface3, surfaces.surface1],
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: gutter,
                  vertical: spacing.gap.xxl,
                ),
                child: Card(
                  margin: EdgeInsets.zero,
                  color: surfaces.surface2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(radii.xl),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: spacing.gap.xl,
                      vertical: spacing.gap.xl,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: colorScheme.primaryContainer,
                            child: Icon(
                              Icons.bubble_chart_rounded,
                              color: colorScheme.onPrimaryContainer,
                              size: 36,
                            ),
                          ),
                          SizedBox(height: spacing.gap.xl),
                          Text(
                            'Welcome to Messie',
                            style: textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          SizedBox(height: spacing.gap.sm),
                          Text(
                            'Stay connected with an encrypted Matrix-first messenger.',
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          SizedBox(height: spacing.gap.xl),
                          if (widget.errorMessage != null)
                            Container(
                              padding: EdgeInsets.all(spacing.gap.lg),
                              margin: EdgeInsets.only(bottom: spacing.gap.xl),
                              decoration: BoxDecoration(
                                color: colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(radii.lg),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.error_outline,
                                      color: colorScheme.onErrorContainer),
                                  SizedBox(width: spacing.gap.sm),
                                  Expanded(
                                    child: Text(
                                      widget.errorMessage!,
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: colorScheme.onErrorContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          TextFormField(
                            controller: _homeserverController,
                            decoration: const InputDecoration(
                              labelText: 'Homeserver URL',
                              hintText: 'https://matrix-client.matrix.org',
                              prefixIcon: Icon(Icons.public_rounded),
                            ),
                            enabled: !widget.isProcessing,
                            keyboardType: TextInputType.url,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Homeserver URL is required';
                              }
                              final trimmed = value.trim();
                              if (!trimmed.startsWith('http://') &&
                                  !trimmed.startsWith('https://')) {
                                return 'Enter a valid URL starting with http or https';
                              }
                              return null;
                            },
                          ),
                          SizedBox(height: spacing.gap.lg),
                          TextFormField(
                            controller: _usernameController,
                            decoration: const InputDecoration(
                              labelText: 'Username or user ID',
                              hintText: '@user:matrix.org',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                            enabled: !widget.isProcessing,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Username is required';
                              }
                              return null;
                            },
                          ),
                          SizedBox(height: spacing.gap.lg),
                          TextFormField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon:
                                  const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off),
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
                          SizedBox(height: spacing.gap.xxl),
                          FilledButton.icon(
                            onPressed: widget.isProcessing
                                ? null
                                : () => _submit(context),
                            icon: widget.isProcessing
                                ? SizedBox(
                                    width: spacing.gap.sm,
                                    height: spacing.gap.sm,
                                    child: const CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.login_rounded),
                            label: Text(widget.isProcessing
                                ? 'Signing in…'
                                : 'Sign in securely'),
                          ),
                          SizedBox(height: spacing.gap.md),
                          Text(
                            'Matrix credentials never leave your device.',
                            textAlign: TextAlign.center,
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
    final roomListState = ref.watch(roomListControllerProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final spacing = MessieSpacing.of(context);
    final surfaces = MessieSurfaces.of(context);
    final colors = MessieColors.of(context);
    final gutter = MessieSpacing.gutter(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messie Messenger'),
        actions: [
          IconButton(
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            tooltip: 'Log out',
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [surfaces.surface3, surfaces.surface1],
          ),
        ),
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: gutter,
            vertical: spacing.gap.xl,
          ),
          children: [
            Card(
              child: Padding(
                padding: EdgeInsets.all(spacing.gap.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: colorScheme.primaryContainer,
                          child: Icon(
                            Icons.verified_user_rounded,
                            color: colorScheme.onPrimaryContainer,
                            size: 28,
                          ),
                        ),
                        SizedBox(width: spacing.gap.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                session.userId,
                                style: textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              SizedBox(height: spacing.gap.xs),
                              Text(
                                session.homeserverUrl,
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (session.deviceId != null) ...[
                      SizedBox(height: spacing.gap.xl),
                      Row(
                        children: [
                          Icon(Icons.devices_rounded,
                              color: colorScheme.primary),
                          SizedBox(width: spacing.gap.sm),
                          Expanded(
                            child: Text(
                              'Device ID: ${session.deviceId}',
                              style: textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ],
                    SizedBox(height: spacing.gap.xl),
                    FilledButton.icon(
                      onPressed: () =>
                          ref.read(authControllerProvider.notifier).logout(),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Log out'),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: spacing.gap.xl),
            Card(
              child: Padding(
                padding: EdgeInsets.all(spacing.gap.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rust bridge status',
                      style: textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: spacing.gap.md),
                    pingState.when(
                      data: (value) => Row(
                        children: [
                          Icon(Icons.check_circle_rounded,
                              color: colors.success),
                          SizedBox(width: spacing.gap.sm),
                          Expanded(child: Text('Rust says: $value')),
                        ],
                      ),
                      loading: () => Row(
                        children: [
                          SizedBox(
                            width: spacing.gap.md,
                            height: spacing.gap.md,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.primary,
                            ),
                          ),
                          SizedBox(width: spacing.gap.sm),
                          const Text('Calling Rust…'),
                        ],
                      ),
                      error: (error, _) => Row(
                        children: [
                          Icon(Icons.error_outline, color: colorScheme.error),
                          SizedBox(width: spacing.gap.sm),
                          Expanded(
                            child: Text('Failed to call Rust: $error'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: spacing.gap.xl),
            Card(
              child: Padding(
                padding: EdgeInsets.all(spacing.gap.xl),
                child: _RoomListSection(
                  state: roomListState,
                  onLoadMore: () => ref
                      .read(roomListControllerProvider.notifier)
                      .loadMoreLp(),
                  onResubscribe: () => ref
                      .read(roomListControllerProvider.notifier)
                      .resubscribeAll(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomListSection extends StatelessWidget {
  const _RoomListSection({
    required this.state,
    required this.onLoadMore,
    required this.onResubscribe,
  });

  final RoomListState state;
  final VoidCallback onLoadMore;
  final VoidCallback onResubscribe;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final spacing = MessieSpacing.of(context);

    if (state.isLoading) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: spacing.gap.lg),
          child: const CircularProgressIndicator(),
        ),
      );
    }

    final children = <Widget>[];

    if (state.error != null) {
      children.add(
        Container(
          padding: EdgeInsets.all(spacing.gap.md),
          margin: EdgeInsets.only(bottom: spacing.gap.md),
          decoration: BoxDecoration(
            color: colors.errorContainer,
            borderRadius: BorderRadius.circular(MessieRadii.of(context).md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_rounded, color: colors.onErrorContainer),
              SizedBox(width: spacing.gap.sm),
              Expanded(
                child: Text(
                  state.error!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.onErrorContainer,
                  ),
                ),
              ),
              IconButton(
                onPressed: onResubscribe,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Retry sync',
              ),
            ],
          ),
        ),
      );
    }

    if (state.hpRooms.isNotEmpty) {
      children.add(Text(
        'Priority rooms',
        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ));
      children.add(SizedBox(height: spacing.gap.sm));
      children.addAll(state.hpRooms.map((room) => _RoomTile(room: room)));
      children.add(SizedBox(height: spacing.gap.lg));
    }

    children.add(Text(
      'All rooms',
      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ));
    children.add(SizedBox(height: spacing.gap.sm));
    if (state.lpRooms.isEmpty) {
      children.add(Text(
        'No additional rooms yet.',
        style: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
      ));
    } else {
      children.addAll(state.lpRooms.map((room) => _RoomTile(room: room)));
    }

    final canLoadMore = state.lpRooms.length < state.lpTotal;
    if (canLoadMore) {
      children.add(SizedBox(height: spacing.gap.md));
      children.add(
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onLoadMore,
            icon: const Icon(Icons.expand_more_rounded),
            label: const Text('Load more conversations'),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.room});

  final RoomPreview room;

  @override
  Widget build(BuildContext context) {
    final spacing = MessieSpacing.of(context);
    final colors = Theme.of(context).colorScheme;
    final unread = room.notificationCount;

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.gap.sm),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MessieRadii.of(context).md),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: spacing.gap.sm),
        leading: _AvatarPlaceholder(name: room.name, avatarUrl: room.avatarUrl),
        title: Text(room.name),
        subtitle: Text(
          room.roomId,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
        trailing: unread > 0
            ? Container(
                padding: EdgeInsets.symmetric(
                  horizontal: spacing.gap.sm,
                  vertical: spacing.gap.xs,
                ),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(spacing.gap.sm),
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: colors.onPrimaryContainer),
                ),
              )
            : null,
      ),
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder({required this.name, this.avatarUrl});

  final String name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    final colors = Theme.of(context).colorScheme;

    return CircleAvatar(
      backgroundColor: colors.secondaryContainer,
      child: Text(
        initials,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: colors.onSecondaryContainer),
      ),
    );
  }

  String _initials(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '?';
    }
    final parts = trimmed.split(RegExp(r'\s+'));
    String result = '';
    if (parts.first.isNotEmpty) {
      result += parts.first[0];
    }
    if (parts.length > 1 && parts.last.isNotEmpty) {
      result += parts.last[0];
    } else if (parts.first.length > 1) {
      result += parts.first[1];
    }
    return result.toUpperCase();
  }
}
