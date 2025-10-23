import 'dart:async';
import 'dart:io';
import 'package:characters/characters.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show consolidateHttpClientResponseBytes;
import 'l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'bridge/messie_bridge.dart';
// Backend API
import 'api/env.dart' as env;
import 'package:dio/dio.dart' as dio;
import 'package:messie_api/messie_api.dart' as api;
import 'state/room_list_controller.dart';
import 'state/timeline_controller.dart';
import 'state/backup_controller.dart';
import 'state/verification_controller.dart';
import 'services/migrations.dart';
import 'services/counts_sync_service.dart';
// Legacy theme remains for reference, but global theme now uses OKLCH builder.
// import 'theme/app_theme.dart';
import 'theme/messie_tokens.dart';
import 'ui/core/back_esc/back_esc_host.dart';
import 'ui/core/back_esc/back_esc_policy.dart';
import 'ui/core/input/input_caps.dart';
import 'ui/core/layout/app_layout.dart';
import 'ui/navigation/app_router.dart';
import 'package:go_router/go_router.dart';
import 'ui/theme/theme_controller.dart';
import 'ui/theme/theme.dart' as messie_theme;
import 'ui/theme/colors.dart' show MessieAccent;
import 'ui/theme/accent_controller.dart';
import 'ui/components/segmented_control.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Run storage migrations before any session-dependent services start.
  await MigrationManager().run();
  runApp(const ProviderScope(child: MessieApp()));
}

final pingProvider = FutureProvider<String>((ref) async {
  return rustPing();
});

final selectedRoomIdProvider = StateProvider<String?>((ref) => null);

final selfTrustProvider = FutureProvider<TrustStateData?>((ref) async {
  final auth = ref.watch(authControllerProvider);
  final session = auth.asData?.value;
  if (session == null) return null;
  final res =
      await rustTrustState(userId: session.userId, deviceId: session.deviceId);
  if (!res.isOk) return null;
  return res.data;
});

class MessieApp extends ConsumerWidget {
  const MessieApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Start/stop classic-sync counts loop when auth session changes.
    ref.listen<AsyncValue<MatrixSession?>>(authControllerProvider,
        (prev, next) {
      final session = next.asData?.value;
      final counts = ref.read(countsSyncProvider.notifier);
      if (session != null) {
        counts.start(
          homeserverUrl: session.homeserverUrl,
          accessToken: session.accessToken,
          userId: session.userId,
        );
      } else {
        counts.stop();
      }
    });
    final themeMode = ref.watch(themeControllerProvider).maybeWhen(
          data: (m) => m,
          orElse: () => ThemeMode.system,
        );
    final accent = ref.watch(accentControllerProvider).maybeWhen(
          data: (a) => a,
          orElse: () => MessieAccent.aqua,
        );

    return MaterialApp.router(
      title: 'Messie',
      theme: messie_theme.MessieThemeBuilder.build(
        brightness: Brightness.light,
        accent: accent,
      ),
      darkTheme: messie_theme.MessieThemeBuilder.build(
        brightness: Brightness.dark,
        accent: accent,
      ),
      themeMode: themeMode,
      debugShowCheckedModeBanner: false,
      routerConfig: buildAppRouter(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => BackEscHost(
        child: AppLayout(
          child: InputCaps(
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class MatrixSession {
  const MatrixSession({
    required this.homeserverUrl,
    required this.userId,
    required this.accessToken,
    this.deviceId,
    this.backendJwt,
  });

  final String homeserverUrl;
  final String userId;
  final String accessToken;
  final String? deviceId;
  final String? backendJwt; // JWT from backend via Matrix OpenID

  MatrixSession copyWith({
    String? accessToken,
    String? deviceId,
    String? backendJwt,
  }) {
    return MatrixSession(
      homeserverUrl: homeserverUrl,
      userId: userId,
      accessToken: accessToken ?? this.accessToken,
      deviceId: deviceId ?? this.deviceId,
      backendJwt: backendJwt ?? this.backendJwt,
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
const _kBackendJwtKey = 'messie.backend_jwt';

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

  // Public helper to ensure backend JWT exists for the current session.
  Future<void> ensureBackendJwt() async {
    final current = state.asData?.value;
    if (current == null) return;
    if (current.backendJwt != null && current.backendJwt!.isNotEmpty) return;
    try {
      var updated = await _fetchAndAttachBackendJwt(current);
      await _persistSession(updated);
      state = AsyncData(updated);
    } catch (_) {
      // ignore; UI may retry
    }
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
      var session = MatrixSession(
        homeserverUrl: data.homeserverUrl,
        userId: data.userId,
        accessToken: data.accessToken,
        deviceId: data.deviceId,
      );
      // Fetch backend JWT via Matrix OpenID
      session = await _fetchAndAttachBackendJwt(session);
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
    final backendJwt = await _secureStorage.read(key: _kBackendJwtKey);

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
    var session = MatrixSession(
      homeserverUrl: data.homeserverUrl,
      userId: data.userId,
      accessToken: accessToken,
      deviceId: data.deviceId ?? deviceId,
      backendJwt: backendJwt,
    );
    // If store has a fresher access token than secure storage, prefer it.
    final fromStore = await _readStoreAccessToken(_basePath);
    if (fromStore != null && fromStore.isNotEmpty && fromStore != session.accessToken) {
      session = session.copyWith(accessToken: fromStore);
    }
    // Optionally refresh backend JWT if missing
    if (session.backendJwt == null || session.backendJwt!.isEmpty) {
      session = await _fetchAndAttachBackendJwt(session);
    }
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
    if (session.backendJwt != null && session.backendJwt!.isNotEmpty) {
      await _secureStorage.write(
          key: _kBackendJwtKey, value: session.backendJwt);
    }
  }

  Future<String?> _readStoreAccessToken(String basePath) async {
    try {
      final file = File(p.join(basePath, 'session.json'));
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final jsonMap = jsonDecode(raw) as Map<String, dynamic>;
      return jsonMap['access_token'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearStoredSession() async {
    await _secureStorage.delete(key: _kHomeserverKey);
    await _secureStorage.delete(key: _kUserIdKey);
    await _secureStorage.delete(key: _kAccessTokenKey);
    await _secureStorage.delete(key: _kDeviceIdKey);
    await _secureStorage.delete(key: _kBackendJwtKey);
  }

  Future<String> _resolveBasePath() async {
    final directory = await getApplicationSupportDirectory();
    final path = p.join(directory.path, 'messie', 'matrix');
    await Directory(path).create(recursive: true);
    return path;
  }
}

extension on AuthController {
  Future<MatrixSession> _fetchAndAttachBackendJwt(MatrixSession session) async {
    try {
      // Derive server name from MXID (@user:server.name)
      final serverName = _extractServerName(session.userId) ??
          _serverNameFromUrl(session.homeserverUrl);
      if (serverName == null) return session;

      // Request Matrix OpenID token from homeserver
      final openId = await _requestMatrixOpenID(
        homeserverUrl: session.homeserverUrl,
        userId: session.userId,
        matrixAccessToken: session.accessToken,
        audience: serverName,
      );

      if (openId == null) return session;

      // Exchange at backend for JWT via generated client
      final backend = api.MessieApi(basePathOverride: env.apiBaseUrl);
      final req = api.MatrixOpenIDRequest((b) => b
        ..accessToken = openId
        ..matrixServerName = serverName);
      final res = await backend
          .getDefaultApi()
          .postMatrixAuth(matrixOpenIDRequest: req);
      final jwt = res.data?.token;
      if (jwt == null || jwt.isEmpty) return session;
      return session.copyWith(backendJwt: jwt);
    } catch (e) {
      debugPrint('OpenID->backend JWT exchange failed: $e');
      return session;
    }
  }

  String? _extractServerName(String mxid) {
    final i = mxid.indexOf(':');
    if (i == -1 || i + 1 >= mxid.length) return null;
    return mxid.substring(i + 1);
  }

  String? _serverNameFromUrl(String url) {
    try {
      final u = Uri.parse(url);
      return u.host.isNotEmpty ? u.host : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _requestMatrixOpenID({
    required String homeserverUrl,
    required String userId,
    required String matrixAccessToken,
    required String audience,
  }) async {
    final client = dio.Dio(dio.BaseOptions(baseUrl: homeserverUrl, headers: {
      'Authorization': 'Bearer $matrixAccessToken',
      'Content-Type': 'application/json',
    }));
    final path =
        '/_matrix/client/v3/user/${Uri.encodeComponent(userId)}/openid/request_token';
    try {
      final resp = await client.post(path, data: {'audience': audience});
      // The response contains { access_token, token_type, matrix_server_name, expires_in }
      final tok = resp.data['access_token'] as String?;
      return tok;
    } catch (e) {
      debugPrint('OpenID request_token failed: $e');
      return null;
    }
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  static DateTime? _lastBackPress;
  static const Duration _exitInterval = Duration(seconds: 2);

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
        // Start backup status stream for this session
        ref.read(backupControllerProvider.notifier).start();
      } else {
        roomList.stop();
        timeline.stop();
        selectedRoom.state = null;
        // Stop backup stream and reset its state
        ref.read(backupControllerProvider.notifier).stop();
        // Reset verification controller state as well
        ref.read(verificationControllerProvider.notifier).cancel();
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

    Widget content;
    if (session != null) {
      content = BackEscSurface(
        priority: SurfacePriority.route,
        onDismiss: () async {
          final popped = await Navigator.of(context).maybePop();
          return popped;
        },
        child: LoggedInView(session: session),
      );
    } else {
      content = BackEscSurface(
        priority: SurfacePriority.route,
        onDismiss: () async {
          final popped = await Navigator.of(context).maybePop();
          return popped;
        },
        child: LoginView(
          isProcessing: authState.isLoading,
          errorMessage: errorText,
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        final handled = await BackEscPolicy.of(context).handleBack();
        if (handled) return;

        final now = DateTime.now();
        final last = _lastBackPress;
        if (last != null && now.difference(last) <= _exitInterval) {
          if (Platform.isAndroid) {
            SystemNavigator.pop();
          }
          return;
        }
        _lastBackPress = now;
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.clearSnackBars();
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('Press back again to exit'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: content,
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
    // Default to local Synapse from Docker for Android emulator.
    _homeserverController = TextEditingController(text: 'http://10.0.2.2:8008');
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
    final l10n = AppLocalizations.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final spacing = MessieSpacing.of(context);
    final radii = MessieRadii.of(context);
    final surfaces = MessieSurfaces.of(context);
    final gutter = MessieSpacing.gutter(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: gutter,
                vertical: spacing.gap.xxl,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: surfaces.surface1,
                  borderRadius: BorderRadius.circular(radii.lg),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
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
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
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
                              return l10n?.login_passwordRequired ??
                                  'Password is required';
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
                              ? (l10n?.login_signingIn ?? 'Signing in…')
                              : (l10n?.login_signIn ?? 'Sign in securely')),
                        ),
                        SizedBox(height: spacing.gap.md),
                        Text(
                          l10n?.login_privacyNote ??
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
      if (Platform.isAndroid &&
          (uri.host == 'localhost' || uri.host == '127.0.0.1')) {
        final rewritten = uri.replace(host: '10.0.2.2').toString();
        if (rewritten != homeserverText) {
          homeserverText = rewritten;
          _homeserverController.text = homeserverText;
          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger?.showSnackBar(
            SnackBar(
              content: Text(
                  AppLocalizations.of(context)?.emulator_host_rewrite ??
                      'Using 10.0.2.2 to reach host from Android emulator'),
              duration: const Duration(seconds: 3),
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
    // Ensure backup status stream is running post-login (still needed for timeline decryption etc.)
    ref.read(backupControllerProvider.notifier).start();
    final roomListState = ref.watch(roomListControllerProvider);
    final timelineState = ref.watch(timelineControllerProvider);
    final selectedRoomId = ref.watch(selectedRoomIdProvider);
    final spacing = MessieSpacing.of(context);
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

    /* Non-chat cards moved to Settings */
    /* final accountCard = Card(
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
            if (trustState.hasValue && trustState.value != null) ...[
              SizedBox(height: spacing.gap.md),
              Wrap(
                spacing: spacing.gap.sm,
                runSpacing: spacing.gap.sm,
                children: [
                  Chip(
                    label: Text(trustState.value!.userVerified ? 'User verified' : 'User unverified'),
                    backgroundColor: trustState.value!.userVerified
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceVariant,
                    labelStyle: textTheme.labelSmall?.copyWith(
                      color: trustState.value!.userVerified
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (trustState.value!.deviceVerified != null)
                    Chip(
                      label: Text(trustState.value!.deviceVerified == true ? 'Device trusted' : 'Device unverified'),
                      backgroundColor: trustState.value!.deviceVerified == true
                          ? colorScheme.tertiaryContainer
                          : colorScheme.surfaceVariant,
                      labelStyle: textTheme.labelSmall?.copyWith(
                        color: trustState.value!.deviceVerified == true
                            ? colorScheme.onTertiaryContainer
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
            SizedBox(height: spacing.gap.lg),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: spacing.gap.xs,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.key_rounded, color: colorScheme.primary),
                    SizedBox(width: spacing.gap.sm),
                    Text(
                      'Recovery & Backup',
                      style: textTheme.titleSmall,
                    ),
                  ],
                ),
                if (backupState.enabled == true && backupState.needsRecovery == false)
                  Chip(
                    label: const Text('Enabled'),
                    backgroundColor: colorScheme.primaryContainer,
                    labelStyle: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                    ),
                  )
                else if (backupState.enabled == true && backupState.needsRecovery != false)
                  Chip(
                    label: const Text('Locked'),
                    backgroundColor: colorScheme.tertiaryContainer,
                    labelStyle: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onTertiaryContainer,
                    ),
                  )
                else if (backupState.enabled == false && backupState.existsOnServer == true)
                  Chip(
                    label: const Text('Available (restore)'),
                    backgroundColor: colorScheme.surfaceVariant,
                    labelStyle: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                else if (backupState.enabled == false)
                  Chip(
                    label: const Text('Disabled'),
                    backgroundColor: colorScheme.errorContainer,
                    labelStyle: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
            SizedBox(height: spacing.gap.md),
            if (backupState.enabled == false && backupState.existsOnServer != true)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _enableBackupFlow(context),
                      icon: const Icon(Icons.cloud_upload_rounded),
                      label: const Text('Turn on Key Backup'),
                    ),
                  ),
                ],
              ),
            if (backupState.enabled == false && backupState.existsOnServer != true)
              SizedBox(height: spacing.gap.sm),
            // Use the same visibility condition as the SAS verification card.
            if (showVerifyRestore)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                  final controller = TextEditingController();
                  final result = await showDialog<bool>(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: const Text('Restore from Recovery Key'),
                      content: TextField(
                        controller: controller,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText: 'Enter your recovery key…',
                        ),
                        autofocus: true,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () async {
                            final raw = controller.text.trim();
                            if (raw.isEmpty) {
                              return;
                            }
                            // Try both spaced and compact variants.
                            var ok = await rustRecoverWithKey(recoveryKey: raw);
                            if (!ok.isOk && raw.contains(' ')) {
                              final compact = raw.replaceAll(RegExp('\\s+'), '');
                              ok = await rustRecoverWithKey(recoveryKey: compact);
                            }
                            if (ok.isOk) {
                              // Offer to save the key securely after a successful recovery
                              final secrets = SecureSecrets();
                              final keyToSave = raw.isNotEmpty ? raw : null;
                              if (keyToSave != null) {
                                final saveOk = await secrets.saveRecoveryKey(keyToSave);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text(saveOk
                                        ? 'Recovery key saved securely'
                                        : 'Failed to save recovery key'),
                                  ));
                                }
                              }
                            }
                            if (context.mounted) {
                              Navigator.of(context).pop(ok.isOk);
                            }
                          },
                          child: const Text('Restore'),
                        ),
                      ],
                    );
                  },
                );
                if (result == true && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Recovery complete – backups enabled')),
                  );
                  // Refresh backup status immediately after recovery
                  await ref.read(backupControllerProvider.notifier).refresh();
                  final rid = ref.read(selectedRoomIdProvider);
                  if (rid != null) {
                    await ref.read(timelineControllerProvider.notifier).openRoom(rid);
                  }
                }
                      },
                      icon: const Icon(Icons.lock_reset_rounded),
                      label: const Text('Restore from Recovery Key'),
                    ),
                  ),
                ],
              ),
            SizedBox(height: spacing.gap.xl),
            FilledButton.icon(
              onPressed: () => ref.read(authControllerProvider.notifier).logout(),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Log out'),
            ),
          ],
        ),
      ),
    ); */

    /* final pingCard = Card(
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
    ); */

    /* final verificationCard = Card(
      child: Padding(
        padding: EdgeInsets.all(spacing.gap.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_rounded, color: colorScheme.primary),
                SizedBox(width: spacing.gap.sm),
                Text('Device Verification', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh trust',
                  onPressed: () => ref.refresh(selfTrustProvider),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            SizedBox(height: spacing.gap.md),
            if (!verifyState.active && verifyState.status == 'idle') ...[
              Text(
                'Verify this device using Short Authentication String (SAS).',
                style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              SizedBox(height: spacing.gap.md),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      await ref
                          .read(verificationControllerProvider.notifier)
                          .start(userId: session.userId, deviceId: null);
                    },
                    icon: const Icon(Icons.verified_user_rounded),
                    label: const Text('Verify This Device'),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Text('Status: ', style: textTheme.bodyMedium),
                  Text(verifyState.status, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  if (verifyState.flowId != null) ...[
                    SizedBox(width: spacing.gap.md),
                    Expanded(
                      child: SelectableText(
                        'Flow: ${verifyState.flowId}',
                        style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ],
              ),
              if (verifyState.error != null) ...[
                SizedBox(height: spacing.gap.sm),
                Text(verifyState.error!, style: textTheme.bodySmall?.copyWith(color: colorScheme.error)),
              ],
              if (verifyState.emoji.isNotEmpty) ...[
                SizedBox(height: spacing.gap.md),
                Text('Compare these emoji on both devices:', style: textTheme.bodySmall),
                SizedBox(height: spacing.gap.sm),
                Wrap(
                  spacing: spacing.gap.md,
                  runSpacing: spacing.gap.sm,
                  children: verifyState.emoji.map((e) => Text(e, style: textTheme.headlineSmall)).toList(),
                ),
              ],
              SizedBox(height: spacing.gap.md),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: verifyState.status == 'keys_exchanged' || verifyState.status == 'ready' || verifyState.status == 'requested'
                        ? () => ref.read(verificationControllerProvider.notifier).confirm()
                        : null,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Confirm'),
                  ),
                  SizedBox(width: spacing.gap.sm),
                  OutlinedButton.icon(
                    onPressed: () => ref.read(verificationControllerProvider.notifier).cancel(),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ); */

    final roomListCard = Padding(
      padding: EdgeInsets.all(spacing.gap.sm),
      child: _RoomListSection(
        state: roomListState,
        onLoadMore: () =>
            ref.read(roomListControllerProvider.notifier).loadMoreLp(),
        onResubscribe: () =>
            ref.read(roomListControllerProvider.notifier).resubscribeAll(),
        onSelectRoom: selectRoom,
        selectedRoomId: selectedRoomId,
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 960;

        // Build main content for list/timeline
        late final Widget content;
        if (isWide) {
          content = Padding(
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
                      roomListCard,
                    ],
                  ),
                ),
                SizedBox(width: spacing.gap.xl),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(spacing.gap.sm),
                    child: buildTimelinePane(),
                  ),
                ),
              ],
            ),
          );
        } else {
          content = AnimatedSwitcher(
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
                              icon:
                                  const Icon(Icons.arrow_back_ios_new_rounded),
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
                          child: buildTimelinePane(isMobile: true),
                        ),
                      ),
                    ],
                  ),
          );
        }

        // Keep AppBar on home list and wide layouts; hide on mobile chat
        final showAppBar = selectedRoomId == null || isWide;
        return Scaffold(
          appBar: showAppBar
              ? AppBar(
                  title: const Text('Messie'),
                  actions: [
                    PopupMenuButton<String>(
                      tooltip: 'Menu',
                      icon: const Icon(Icons.more_vert_rounded),
                      onSelected: (value) {
                        switch (value) {
                          case 'settings':
                            context.push('/settings');
                            break;
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem<String>(
                          value: 'settings',
                          child: Text('Settings'),
                        ),
                      ],
                    ),
                  ],
                )
              : null,
          body: SafeArea(child: content),
        );
      },
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

    // Simple filter segmented control (visual only for now)
    Widget filters() {
      return Padding(
        padding: EdgeInsets.only(bottom: spacing.gap.md),
        child: MessieSegmentedControl<String>(
          value: 'all',
          // Remove 'unread' option since Synapse sliding sync doesn't provide counts
          segments: const ['all', 'favorites'],
          labelBuilder: (s) => Text(
            switch (s) {
              'favorites' => 'Favorites',
              _ => 'All',
            },
          ),
          onChanged: (_) {},
        ),
      );
    }

    if (state.isLoading) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: spacing.gap.lg),
          child: const CircularProgressIndicator(),
        ),
      );
    }

    final children = <Widget>[];

    // Top filters
    children.add(filters());

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
          onToggleMute: () async {
            final res = await rustSetRoomMute(
                roomId: room.roomId, muted: !room.isMuted);
            if (!res.isOk && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(res.error ?? 'Failed to update mute state')),
              );
            } else {
              onResubscribe();
            }
          },
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
          onToggleMute: () async {
            final res = await rustSetRoomMute(
                roomId: room.roomId, muted: !room.isMuted);
            if (!res.isOk && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(res.error ?? 'Failed to update mute state')),
              );
            } else {
              onResubscribe();
            }
          },
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
    this.onToggleMute,
  });

  final RoomPreview room;
  final VoidCallback onTap;
  final bool isActive;
  final VoidCallback? onToggleMute;

  @override
  Widget build(BuildContext context) {
    final spacing = MessieSpacing.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isMuted = room.isMuted;

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.gap.sm),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MessieRadii.of(context).md),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: spacing.gap.md,
          vertical: spacing.gap.xs,
        ),
        leading: _AvatarPlaceholder(name: room.name, avatarUrl: room.avatarUrl),
        title: Text(room.name),
        selected: isActive,
        onTap: onTap,
        selectedTileColor: scheme.secondaryContainer,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (room.highlightCount > 0 || room.notificationCount > 0)
              _CountBadge(
                count: room.highlightCount > 0
                    ? room.highlightCount
                    : room.notificationCount,
                isHighlight: room.highlightCount > 0,
              ),
            SizedBox(width: room.highlightCount > 0 || room.notificationCount > 0 ? spacing.gap.sm : 0),
            IconButton(
              visualDensity: VisualDensity.compact,
              splashRadius: 18,
              icon: Icon(
                isMuted
                    ? Icons.notifications_off_rounded
                    : Icons.notifications_none_rounded,
              ),
              tooltip: isMuted ? 'Unmute notifications' : 'Mute notifications',
              onPressed: onToggleMute,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarPlaceholder extends ConsumerStatefulWidget {
  const _AvatarPlaceholder({required this.name, this.avatarUrl});

  final String name;
  final String? avatarUrl;

  @override
  ConsumerState<_AvatarPlaceholder> createState() => _AvatarPlaceholderState();
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, this.isHighlight = false});
  final int count;
  final bool isHighlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = isHighlight ? scheme.primary : scheme.secondaryContainer;
    final fg = isHighlight ? scheme.onPrimary : scheme.onSecondaryContainer;
    final text = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      constraints: const BoxConstraints(minWidth: 24, minHeight: 20),
      alignment: Alignment.center,
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SenderAvatar extends ConsumerStatefulWidget {
  const _SenderAvatar({required this.roomId, required this.userId});

  final String roomId;
  final String userId;

  @override
  ConsumerState<_SenderAvatar> createState() => _SenderAvatarState();
}

class _SenderName extends ConsumerStatefulWidget {
  const _SenderName({required this.roomId, required this.userId});

  final String roomId;
  final String userId;

  @override
  ConsumerState<_SenderName> createState() => _SenderNameState();
}

class _SenderNameState extends ConsumerState<_SenderName> {
  MemberProfileData? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _SenderName oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId ||
        oldWidget.userId != widget.userId) {
      _load();
    }
  }

  Future<void> _load() async {
    final res =
        await rustMemberProfile(roomId: widget.roomId, userId: widget.userId);
    if (!mounted) return;
    if (res.isOk && res.data != null) {
      setState(() {
        _profile = res.data;
      });
    } else {
      setState(() {
        _profile = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    String name = _profile?.displayName ?? widget.userId;
    // If userId looks like @local:server, collapse to local part for readability
    final at = name.indexOf(':');
    if (name.startsWith('@') && at > 1) {
      name = name.substring(1, at);
    }
    return Text(
      name,
      style: textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _SenderAvatarState extends ConsumerState<_SenderAvatar> {
  static final Map<String, MemberProfileData> _cache =
      <String, MemberProfileData>{};
  MemberProfileData? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _SenderAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId ||
        oldWidget.userId != widget.userId) {
      _load();
    }
  }

  Future<void> _load() async {
    final key = '${widget.roomId}::${widget.userId}';
    final cached = _cache[key];
    if (cached != null) {
      setState(() {
        _profile = cached;
      });
      return;
    }
    final res =
        await rustMemberProfile(roomId: widget.roomId, userId: widget.userId);
    if (!mounted) return;
    if (res.isOk && res.data != null) {
      _cache[key] = res.data!;
      setState(() {
        _profile = res.data;
      });
    } else {
      // Keep null; fallback to initials from user id
      setState(() {
        _profile = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _profile?.displayName ?? widget.userId;
    final url = _profile?.avatarUrl;
    return _AvatarPlaceholder(name: name, avatarUrl: url);
  }
}

class _AvatarPlaceholderState extends ConsumerState<_AvatarPlaceholder> {
  String? _httpUrl;
  String? _filePath;

  @override
  void didUpdateWidget(covariant _AvatarPlaceholder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUrl != widget.avatarUrl) {
      _resolve();
    }
  }

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final mxc = widget.avatarUrl;
    if (mxc == null || mxc.isEmpty || !mxc.startsWith('mxc://')) {
      if (mounted) setState(() { _httpUrl = null; _filePath = null; });
      return;
    }
    final res = await rustMxcToHttp(mxc: mxc, w: 96, h: 96);
    if (!res.isOk || res.data == null) {
      if (mounted) setState(() { _httpUrl = null; _filePath = null; });
      return;
    }
    final httpUrl = res.data!;

    // Check persistent cache first
    final dir = await getApplicationSupportDirectory();
    final cacheDir = Directory(p.join(dir.path, 'messie', 'media', 'avatars'));
    try { await cacheDir.create(recursive: true); } catch (_) {}
    final key = _avatarCacheKey(mxc, w: 96, h: 96);
    final target = File(p.join(cacheDir.path, '$key'));
    if (await target.exists()) {
      if (mounted) setState(() { _filePath = target.path; _httpUrl = null; });
      return;
    }

    // Download and persist
    final session = ref.read(authControllerProvider).asData?.value;
    try {
      final client = HttpClient();
      final uri = Uri.parse(httpUrl);
      final req = await client.getUrl(uri);
      if (session != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${session.accessToken}');
      }
      final resp = await req.close();
      if (resp.statusCode == 200) {
        final bytes = await consolidateHttpClientResponseBytes(resp);
        await target.writeAsBytes(bytes, flush: true);
        if (mounted) setState(() { _filePath = target.path; _httpUrl = null; });
      } else {
        if (mounted) setState(() => _httpUrl = httpUrl);
      }
      client.close(force: true);
    } catch (_) {
      if (mounted) setState(() => _httpUrl = httpUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initials = _initials(widget.name);
    final colors = Theme.of(context).colorScheme;
    final url = _httpUrl;
    final filePath = _filePath;
    final session = ref.watch(authControllerProvider).asData?.value;
    final headers = session != null
        ? <String, String>{'Authorization': 'Bearer ${session.accessToken}'}
        : null;

    if (filePath != null && filePath.isNotEmpty && File(filePath).existsSync()) {
      return CircleAvatar(
        backgroundColor: colors.secondaryContainer,
        child: ClipOval(
          child: Image.file(
            File(filePath),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Text(
                  initials,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: colors.onSecondaryContainer),
                ),
              );
            },
          ),
        ),
      );
    }
    if (url != null && url.isNotEmpty) {
      // Use Image.network with errorBuilder to avoid global image exceptions
      // when the thumbnail endpoint returns 404. Fallback to initials.
      return CircleAvatar(
        backgroundColor: colors.secondaryContainer,
        child: ClipOval(
          child: Image.network(
            url,
            headers: headers,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Text(
                  initials,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: colors.onSecondaryContainer),
                ),
              );
            },
          ),
        ),
      );
    }
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

  String _avatarCacheKey(String mxc, {required int w, required int h}) {
    // Stable filename: sanitize mxc and include size
    final base = mxc.replaceAll('mxc://', '');
    final size = 'w${w}h$h';
    final sanitized = base.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return '${sanitized}_$size';
  }

  String _initials(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '?';
    }
    final parts = trimmed.split(RegExp(r'\s+'));

    String takeFirstGrapheme(String s) {
      final chars = s.characters;
      if (chars.isEmpty) return '';
      return chars.first;
    }

    String takeSecondGrapheme(String s) {
      final chars = s.characters;
      if (chars.isEmpty) return '';
      final rest = chars.skip(1);
      if (rest.isEmpty) return '';
      return rest.first;
    }

    String result = '';
    // First initial from first word
    result += takeFirstGrapheme(parts.first);
    // Second initial from last word (if multiple), otherwise second grapheme of first word
    if (parts.length > 1) {
      result += takeFirstGrapheme(parts.last);
    } else {
      result += takeSecondGrapheme(parts.first);
    }
    return result.isEmpty ? '?' : result.toUpperCase();
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
  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  TimelineItem? _replyTo;
  bool _showJumpToLatest = false;

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
    // Show "Jump to latest" when user is scrolled away from bottom.
    final distanceFromBottom =
        _controller.position.maxScrollExtent - _controller.offset;
    final shouldShow = distanceFromBottom > 200;
    if (shouldShow != _showJumpToLatest) {
      setState(() {
        _showJumpToLatest = shouldShow;
      });
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
          // Mark read up to latest event when we are at the bottom.
          final last =
              widget.state.events.isNotEmpty ? widget.state.events.last : null;
          final lastEventId = last?.key.eventId;
          final roomId = widget.selectedRoomId;
          if (lastEventId != null && roomId != null) {
            // Fire-and-forget; UI does not block on this.
            unawaited(rustMarkReadUpTo(roomId: roomId, eventId: lastEventId));
          }
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
    _composer.dispose();
    _composerFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<TimelineState>(
        timelineControllerProvider, _handleTimelineChange);

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

    Future<void> sendMessage() async {
      final roomId = widget.selectedRoomId;
      final text = _composer.text.trim();
      if (roomId == null || text.isEmpty) return;
      final replyTo = _replyTo?.key.eventId;
      final messenger = ScaffoldMessenger.of(context);
      final res =
          await rustSendText(roomId: roomId, body: text, replyTo: replyTo);
      if (!res.isOk && mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(res.error ?? 'Failed to send')),
        );
      }
      if (mounted) {
        _composer.clear();
        setState(() {
          _replyTo = null;
        });
      }
    }

    final built = LayoutBuilder(
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
            return Center(
              child: Text(
                'No messages yet.',
                style: textTheme.bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            );
          }

          return ListView.builder(
            controller: _controller,
            padding: EdgeInsets.only(bottom: spacing.gap.lg),
            physics: hasBoundedHeight ? null : const ClampingScrollPhysics(),
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
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                return const SizedBox(height: 12);
              }

              final item = events[index - 1];
              final roomId = widget.selectedRoomId!;
              return Padding(
                padding: EdgeInsets.only(bottom: spacing.gap.sm),
                child: item.isOwn
                    ? _TimelineBubble(
                        item: item,
                        onLongPress: () {
                          if (item.key.eventId != null) {
                            setState(() {
                              _replyTo = item;
                            });
                            _composerFocus.requestFocus();
                          }
                        },
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SenderAvatar(roomId: roomId, userId: item.sender),
                          SizedBox(width: spacing.gap.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: EdgeInsets.only(
                                      left: spacing.gap.xs,
                                      bottom: spacing.gap.xs),
                                  child: _SenderName(
                                      roomId: roomId, userId: item.sender),
                                ),
                                _TimelineBubble(
                                  item: item,
                                  onLongPress: () {
                                    if (item.key.eventId != null) {
                                      setState(() {
                                        _replyTo = item;
                                      });
                                      _composerFocus.requestFocus();
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              );
            },
          );
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
        final stack = Stack(
          children: [
            Positioned.fill(child: buildList()),
            if (_showJumpToLatest && events.isNotEmpty)
              Positioned(
                right: 8,
                bottom: (widget.selectedRoomId != null) ? 72 : 8,
                child: FloatingActionButton.extended(
                  heroTag: 'jump_to_latest',
                  onPressed: () async {
                    if (_controller.hasClients) {
                      await _controller.animateTo(
                        _controller.position.maxScrollExtent,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                      );
                    }
                    // Mark read up to latest event as we jump.
                    final last = widget.state.events.isNotEmpty
                        ? widget.state.events.last
                        : null;
                    final lastEventId = last?.key.eventId;
                    final roomId = widget.selectedRoomId;
                    if (lastEventId != null && roomId != null) {
                      unawaited(rustMarkReadUpTo(
                          roomId: roomId, eventId: lastEventId));
                    }
                    if (mounted) {
                      setState(() {
                        _showJumpToLatest = false;
                      });
                    }
                  },
                  icon: const Icon(Icons.arrow_downward_rounded),
                  label: const Text('Jump to latest'),
                ),
              ),
          ],
        );

        if (hasBoundedHeight) {
          children.add(Expanded(child: stack));
        } else {
          children.add(SizedBox(height: _mobileTimelineHeight, child: stack));
        }

        // Composer (reply banner + input)
        if (widget.selectedRoomId != null) {
          if (_replyTo != null) {
            children.add(
              Padding(
                padding: EdgeInsets.only(top: spacing.gap.md),
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius:
                        BorderRadius.circular(MessieRadii.of(context).md),
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: spacing.gap.md,
                    vertical: spacing.gap.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Replying to: ${_replyTo!.body ?? '[message]'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cancel reply',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          setState(() {
                            _replyTo = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          children.add(
            Padding(
              padding: EdgeInsets.only(top: spacing.gap.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Shortcuts(
                      shortcuts: <ShortcutActivator, Intent>{
                        SingleActivator(LogicalKeyboardKey.enter):
                            const ActivateIntent(),
                      },
                      child: Actions(
                        actions: <Type, Action<Intent>>{
                          ActivateIntent: CallbackAction<ActivateIntent>(
                            onInvoke: (intent) {
                              sendMessage();
                              return null;
                            },
                          ),
                        },
                        child: TextField(
                          focusNode: _composerFocus,
                          controller: _composer,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'Type a message',
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: spacing.gap.sm),
                  FilledButton(
                    onPressed: sendMessage,
                    child: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          mainAxisSize: hasBoundedHeight ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      },
    );

    // On mobile (when an explicit onClose is provided), intercept system back
    // to close the conversation instead of attempting to pop the root route.
    if (widget.onClose != null) {
      return BackEscSurface(
        priority: SurfacePriority.route,
        onDismiss: () async {
          widget.onClose?.call();
          return true;
        },
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (!didPop) {
              widget.onClose?.call();
            }
          },
          child: built,
        ),
      );
    }

    return built;
  }
}

class _TimelineBubble extends StatelessWidget {
  const _TimelineBubble({required this.item, this.onLongPress});

  final TimelineItem item;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final spacing = MessieSpacing.of(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Improve contrast: own = primaryContainer, others = surfaceContainer with outline.
    final bool isOwn = item.isOwn;
    final background =
        isOwn ? scheme.primaryContainer : scheme.surfaceContainer;
    final foreground = isOwn ? scheme.onPrimaryContainer : scheme.onSurface;

    final timestamp = item.timestamp != null
        ? TimeOfDay.fromDateTime(item.timestamp!.toLocal())
        : null;

    return Align(
      alignment: item.isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GestureDetector(
          onLongPress: onLongPress,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(spacing.gap.md),
                topRight: Radius.circular(spacing.gap.md),
                bottomLeft:
                    Radius.circular(isOwn ? spacing.gap.md : spacing.gap.sm),
                bottomRight:
                    Radius.circular(isOwn ? spacing.gap.sm : spacing.gap.md),
              ),
              border: isOwn ? null : Border.all(color: scheme.outlineVariant),
            ),
            child: Padding(
              padding: EdgeInsets.all(spacing.gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                            ?.copyWith(color: foreground.withValues(alpha: 0.7)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Moved RecoveryKeyDialog to settings screen; removed here to avoid unused warnings.
