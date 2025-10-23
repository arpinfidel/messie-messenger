import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart' as dio;

import '../api/env.dart' as env;
import 'package:messie_api/messie_api.dart' as api;
import '../bridge/messie_bridge.dart';

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
