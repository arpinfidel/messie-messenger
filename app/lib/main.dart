import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'bridge/messie_bridge.dart';
import 'state/room_list_controller.dart';
import 'state/timeline_controller.dart';
import 'theme/app_theme.dart';
import 'theme/messie_tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MessieApp()));
}

final pingProvider = FutureProvider<String>((ref) async {
  return rustPing();
});

final selectedRoomIdProvider = StateProvider<String?>((ref) => null);

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
      final timeline = ref.read(timelineControllerProvider.notifier);
      final selectedRoom = ref.read(selectedRoomIdProvider.notifier);

      if (session != null) {
        roomList.start();
      } else {
        roomList.stop();
        timeline.stop();
        selectedRoom.state = null;
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
    var homeserverText = _homeserverController.text.trim();

    // On Android emulator, rewrite localhost/127.0.0.1 to 10.0.2.2 and inform the user.
    try {
      final uri = Uri.parse(homeserverText);
      if (Platform.isAndroid && (uri.host == 'localhost' || uri.host == '127.0.0.1')) {
        final rewritten = uri.replace(host: '10.0.2.2').toString();
        if (rewritten != homeserverText) {
          homeserverText = rewritten;
          _homeserverController.text = homeserverText;
          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger?.showSnackBar(
            const SnackBar(
              content: Text('Using 10.0.2.2 to reach host from Android emulator'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (_) {
      // If parse fails, proceed without rewrite.
    }

    await ref.read(authControllerProvider.notifier).login(
          homeserverUrl: homeserverText,
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
    final timelineState = ref.watch(timelineControllerProvider);
    final selectedRoomId = ref.watch(selectedRoomIdProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final spacing = MessieSpacing.of(context);
    final surfaces = MessieSurfaces.of(context);
    final colors = MessieColors.of(context);
    final gutter = MessieSpacing.gutter(context);

    void selectRoom(String roomId) {
      if (ref.read(selectedRoomIdProvider) == roomId) {
        return;
      }
      ref.read(selectedRoomIdProvider.notifier).state = roomId;
      ref.read(timelineControllerProvider.notifier).openRoom(roomId);
    }

    void closeRoom() {
      ref.read(selectedRoomIdProvider.notifier).state = null;
      ref.read(timelineControllerProvider.notifier).stop();
    }

    RoomPreview? selectedRoom;
    if (selectedRoomId != null) {
      for (final room in [
        ...roomListState.hpRooms,
        ...roomListState.lpRooms,
      ]) {
        if (room.roomId == selectedRoomId) {
          selectedRoom = room;
          break;
        }
      }
    }

    final accountCard = Card(
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
                        style:
                            textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
                  Icon(Icons.devices_rounded, color: colorScheme.primary),
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
              onPressed: () => ref.read(authControllerProvider.notifier).logout(),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Log out'),
            ),
          ],
        ),
      ),
    );

    final pingCard = Card(
      child: Padding(
        padding: EdgeInsets.all(spacing.gap.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rust bridge status',
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: spacing.gap.md),
            pingState.when(
              data: (value) => Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: colors.success),
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
                  Expanded(child: Text('Failed to call Rust: $error')),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final roomListCard = Card(
      child: Padding(
        padding: EdgeInsets.all(spacing.gap.xl),
        child: _RoomListSection(
          state: roomListState,
          onLoadMore: () =>
              ref.read(roomListControllerProvider.notifier).loadMoreLp(),
          onResubscribe: () =>
              ref.read(roomListControllerProvider.notifier).resubscribeAll(),
          onSelectRoom: selectRoom,
          selectedRoomId: selectedRoomId,
        ),
      ),
    );

    Widget buildTimelinePane({bool isMobile = false}) {
      return _TimelinePane(
        state: timelineState,
        selectedRoomId: selectedRoomId,
        room: selectedRoom,
        onClose: isMobile ? closeRoom : null,
      );
    }

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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 960;
            if (isWide) {
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: gutter,
                  vertical: spacing.gap.xl,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 320,
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          accountCard,
                          SizedBox(height: spacing.gap.xl),
                          pingCard,
                          SizedBox(height: spacing.gap.xl),
                          roomListCard,
                        ],
                      ),
                    ),
                    SizedBox(width: spacing.gap.xl),
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(spacing.gap.lg),
                          child: buildTimelinePane(),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: selectedRoomId == null
                  ? ListView(
                      key: const ValueKey('mobile-list'),
                      padding: EdgeInsets.symmetric(
                        horizontal: gutter,
                        vertical: spacing.gap.xl,
                      ),
                      children: [
                        accountCard,
                        SizedBox(height: spacing.gap.xl),
                        pingCard,
                        SizedBox(height: spacing.gap.xl),
                        roomListCard,
                      ],
                    )
                  : Column(
                      key: const ValueKey('mobile-timeline'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: EdgeInsets.all(spacing.gap.md),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                                tooltip: 'Close conversation',
                                onPressed: closeRoom,
                              ),
                              Expanded(
                                child: Text(
                                  selectedRoom?.name ?? 'Conversation',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: gutter,
                              vertical: spacing.gap.md,
                            ),
                            child: Card(
                              child: Padding(
                                padding: EdgeInsets.all(spacing.gap.lg),
                                child: buildTimelinePane(isMobile: true),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            );
          },
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
    required this.onSelectRoom,
    this.selectedRoomId,
  });

  final RoomListState state;
  final VoidCallback onLoadMore;
  final VoidCallback onResubscribe;
  final void Function(String roomId) onSelectRoom;
  final String? selectedRoomId;

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
      children.addAll(state.hpRooms.map(
        (room) => _RoomTile(
          room: room,
          isActive: selectedRoomId == room.roomId,
          onTap: () => onSelectRoom(room.roomId),
        ),
      ));
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
      children.addAll(state.lpRooms.map(
        (room) => _RoomTile(
          room: room,
          isActive: selectedRoomId == room.roomId,
          onTap: () => onSelectRoom(room.roomId),
        ),
      ));
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
  const _RoomTile({
    required this.room,
    required this.onTap,
    this.isActive = false,
  });

  final RoomPreview room;
  final VoidCallback onTap;
  final bool isActive;

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
        selected: isActive,
        onTap: onTap,
        selectedTileColor: colors.primaryContainer.withOpacity(0.2),
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

class _TimelinePane extends ConsumerStatefulWidget {
  const _TimelinePane({
    required this.state,
    required this.selectedRoomId,
    required this.room,
    this.onClose,
  });

  final TimelineState state;
  final String? selectedRoomId;
  final RoomPreview? room;
  final VoidCallback? onClose;

  @override
  ConsumerState<_TimelinePane> createState() => _TimelinePaneState();
}

class _TimelinePaneState extends ConsumerState<_TimelinePane> {
  late final ScrollController _controller;
  static const double _mobileTimelineHeight = 420;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _controller.addListener(_handleScroll);
  }

  void _handleScroll() {
    final state = widget.state;
    if (!mounted || !_controller.hasClients) {
      return;
    }
    if (_controller.position.pixels <= 80 &&
        !state.isLoadingMore &&
        !state.reachedStart &&
        !state.isLoading) {
      ref.read(timelineControllerProvider.notifier).loadOlder();
    }
  }

  void _handleTimelineChange(TimelineState? previous, TimelineState next) {
    final change = next.lastChange;
    if (change == null) {
      return;
    }

    if (change.op == TimelineOp.prepend && _controller.hasClients) {
      final before = _controller.position.maxScrollExtent;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) return;
        final after = _controller.position.maxScrollExtent;
        final delta = after - before;
        if (delta > 0) {
          _controller.jumpTo(_controller.offset + delta);
        }
        ref.read(timelineControllerProvider.notifier).acknowledgeChange();
      });
      return;
    }

    if (change.op == TimelineOp.append && _controller.hasClients) {
      final distanceFromBottom =
          _controller.position.maxScrollExtent - _controller.offset;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) return;
        if (distanceFromBottom < 120) {
          _controller.animateTo(
            _controller.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
        ref.read(timelineControllerProvider.notifier).acknowledgeChange();
      });
      return;
    }

    if (change.op == TimelineOp.reset && _controller.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_controller.hasClients) {
          _controller.jumpTo(_controller.position.maxScrollExtent);
        }
        ref.read(timelineControllerProvider.notifier).acknowledgeChange();
      });
      return;
    }

    ref.read(timelineControllerProvider.notifier).acknowledgeChange();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<TimelineState>(timelineControllerProvider, _handleTimelineChange);

    final state = widget.state;
    final spacing = MessieSpacing.of(context);
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    if (widget.selectedRoomId == null) {
      return Center(
        child: Text(
          'Select a room to see messages.',
          style: textTheme.bodyMedium,
        ),
      );
    }

    if (state.isLoading && state.events.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final events = state.events;

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedHeight = constraints.maxHeight.isFinite;

        Widget buildErrorBanner() {
          if (state.error == null) {
            return const SizedBox.shrink();
          }
          return Container(
            padding: EdgeInsets.all(spacing.gap.md),
            margin: EdgeInsets.only(bottom: spacing.gap.md),
            decoration: BoxDecoration(
              color: colors.errorContainer,
              borderRadius: BorderRadius.circular(MessieRadii.of(context).md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_rounded,
                    color: colors.onErrorContainer, size: 20),
                SizedBox(width: spacing.gap.sm),
                Expanded(
                  child: Text(
                    state.error!,
                    style: textTheme.bodyMedium
                        ?.copyWith(color: colors.onErrorContainer),
                  ),
                ),
              ],
            ),
          );
        }

        Widget buildList() {
          if (events.isEmpty) {
            final child = Center(
              child: Text(
                'No messages yet.',
                style: textTheme.bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            );

            if (hasBoundedHeight) {
              return Expanded(child: child);
            }
            return SizedBox(height: _mobileTimelineHeight, child: child);
          }

          final listView = ListView.builder(
            controller: _controller,
            padding: EdgeInsets.only(bottom: spacing.gap.lg),
            physics:
                hasBoundedHeight ? null : const ClampingScrollPhysics(),
            shrinkWrap: !hasBoundedHeight,
            itemCount: events.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                if (state.reachedStart) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: spacing.gap.sm),
                    child: Text(
                      'Beginning of history',
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                if (state.isLoadingMore) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                return const SizedBox(height: 12);
              }

              final item = events[index - 1];
              return Padding(
                padding: EdgeInsets.only(bottom: spacing.gap.sm),
                child: _TimelineBubble(item: item),
              );
            },
          );

          if (hasBoundedHeight) {
            return Expanded(child: listView);
          }
          return SizedBox(height: _mobileTimelineHeight, child: listView);
        }

        final children = <Widget>[];
        if (widget.onClose == null && widget.room != null) {
          children.add(
            Padding(
              padding: EdgeInsets.only(bottom: spacing.gap.md),
              child: Text(
                widget.room!.name,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        }
        if (state.error != null) {
          children.add(buildErrorBanner());
        }
        children.add(buildList());

        return Column(
          mainAxisSize:
              hasBoundedHeight ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      },
    );
  }
}

class _TimelineBubble extends StatelessWidget {
  const _TimelineBubble({required this.item});

  final TimelineItem item;

  @override
  Widget build(BuildContext context) {
    final spacing = MessieSpacing.of(context);
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final background = item.isOwn ? colors.primary : colors.surfaceVariant;
    final foreground =
        item.isOwn ? colors.onPrimary : colors.onSurfaceVariant;

    final timestamp = item.timestamp != null
        ? TimeOfDay.fromDateTime(item.timestamp!.toLocal())
        : null;

    return Align(
      alignment:
          item.isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(spacing.gap.md),
          ),
          child: Padding(
            padding: EdgeInsets.all(spacing.gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.sender,
                  style: textTheme.labelMedium
                      ?.copyWith(color: foreground.withOpacity(0.8)),
                ),
                SizedBox(height: spacing.gap.xs),
                Text(
                  item.body ?? '[Unsupported message]',
                  style: textTheme.bodyMedium?.copyWith(color: foreground),
                ),
                if (timestamp != null)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      timestamp.format(context),
                      style: textTheme.labelSmall
                          ?.copyWith(color: foreground.withOpacity(0.7)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
