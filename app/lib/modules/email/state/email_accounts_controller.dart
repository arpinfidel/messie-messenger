import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:io' show Platform;

import '../services/email_account.dart';
import '../../../api/google_oauth.dart';
import '../../../api/imap_oauth.dart';

const _kEmailAccountsKey = 'messie.email.accounts';

final emailAccountsProvider = FutureProvider<List<EmailAccountConfig>>((ref) async {
  const storage = FlutterSecureStorage();
  final raw = await storage.read(key: _kEmailAccountsKey);
  if (raw == null || raw.isEmpty) return const <EmailAccountConfig>[];
  try {
    final list = (jsonDecode(raw) as List).cast<Map>().map((e) => EmailAccountConfig.fromJson(e.cast<String, dynamic>())).toList();
    return list;
  } catch (_) {
    return const <EmailAccountConfig>[];
  }
});

final emailAccountsControllerProvider = Provider<EmailAccountsController>((ref) => EmailAccountsController(ref));

class EmailAccountsController {
  EmailAccountsController(this._ref);
  final Ref _ref;

  Future<void> addAccount(EmailAccountConfig config) async {
    const storage = FlutterSecureStorage();
    final existing = await _ref.read(emailAccountsProvider.future);
    final next = [...existing, config];
    final jsonList = next.map((e) => e.toJson()).toList();
    await storage.write(key: _kEmailAccountsKey, value: jsonEncode(jsonList));
    _ref.invalidate(emailAccountsProvider);
  }

  Future<void> replaceAccount(EmailAccountConfig oldCfg, EmailAccountConfig newCfg) async {
    const storage = FlutterSecureStorage();
    final existing = await _ref.read(emailAccountsProvider.future);
    final list = [...existing];
    final idx = list.indexWhere((e) => _sameAccount(e, oldCfg));
    if (idx != -1) {
      list[idx] = newCfg;
    } else {
      list.add(newCfg);
    }
    final jsonList = list.map((e) => e.toJson()).toList();
    await storage.write(key: _kEmailAccountsKey, value: jsonEncode(jsonList));
    _ref.invalidate(emailAccountsProvider);
  }

  bool _sameAccount(EmailAccountConfig a, EmailAccountConfig b) {
    return a.provider == b.provider && a.email == b.email && a.imapHost == b.imapHost && a.username == b.username;
  }

  Future<EmailAccountConfig> ensureFreshAccessToken(EmailAccountConfig account, {bool force = false}) async {
    if (account.authType != 'oauth2') return account;
    final refreshToken = account.oauthRefreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return account;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final expiryMs = account.oauthExpiryEpochMs ?? 0;
    final needsRefresh = force || expiryMs == 0 || nowMs >= (expiryMs - 60 * 1000);
    if (!needsRefresh) {
      debugPrint('[oauth] token still valid; skip refresh (force=$force, expiresAt=$expiryMs, now=$nowMs)');
      return account;
    }

    try {
      final dio = Dio();
      String clientId = '';
      String? clientSecret;
      String tokenEndpoint = '';

      // Prefer client info persisted with the account (source of the token)
      final persistedClientId = account.oauthClientId;
      final persistedTokenEndpoint = account.oauthTokenEndpoint;
      if (persistedClientId != null && persistedClientId.isNotEmpty) {
        clientId = persistedClientId;
      }
      if (persistedTokenEndpoint != null && persistedTokenEndpoint.isNotEmpty) {
        tokenEndpoint = persistedTokenEndpoint;
      }

      // If still missing, consult IMAP OAuth provider config.
      final imap = await ImapOAuthConfig.load();
      ImapOAuthProviderConfig? prov;
      if (imap.providers.isNotEmpty) {
        prov = imap.providers.firstWhere(
          (p) => p.id == (account.provider ?? ''),
          orElse: () => imap.providers.first,
        );
      }
      if (prov != null) {
        clientId = (Platform.isIOS ? prov.iosClientId : prov.androidClientId).isNotEmpty
            ? (Platform.isIOS ? prov.iosClientId : prov.androidClientId)
            : prov.androidClientId;
        clientSecret = (prov.clientSecret != null && prov.clientSecret!.isNotEmpty)
            ? prov.clientSecret!
            : null;
        if ((prov.tokenEndpoint ?? '').isNotEmpty) {
          tokenEndpoint = prov.tokenEndpoint!;
        } else if ((prov.issuer).isNotEmpty) {
          final disc = await dio.get('${prov.issuer}/.well-known/openid-configuration');
          tokenEndpoint = disc.data['token_endpoint'] as String;
        }
      }

      // Fallback to GoogleOAuth config if still missing
      if (clientId.isEmpty) {
        final cfg = await GoogleOAuth.load();
        clientId = Platform.isIOS ? cfg.iosClientId : cfg.androidClientId;
      }
      if (tokenEndpoint.isEmpty) tokenEndpoint = 'https://oauth2.googleapis.com/token';
      debugPrint('[oauth] using client_id=$clientId endpoint=$tokenEndpoint');

      final form = <String, dynamic>{
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': clientId,
      };
      if (clientSecret != null && clientSecret.isNotEmpty) {
        form['client_secret'] = clientSecret;
      }
      debugPrint('[oauth] refreshing (provider=${account.provider}) endpoint=$tokenEndpoint');
      final resp = await dio.post(
        tokenEndpoint,
        data: form,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.json,
          validateStatus: (s) => true,
        ),
      );
      if (resp.statusCode != 200) {
        debugPrint('[oauth] refresh failed: status=${resp.statusCode} body=${resp.data}');
        return account;
      }
      final data = resp.data as Map<String, dynamic>;
      final newAccess = data['access_token'] as String?;
      if (newAccess == null || newAccess.isEmpty) {
        debugPrint('[oauth] refresh response missing access_token: $data');
        return account;
      }
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
      final newExpiry = DateTime.now().add(Duration(seconds: expiresIn)).millisecondsSinceEpoch;
      final newIdToken = data['id_token'] as String?;
      final updated = account.copyWith(
        oauthAccessToken: newAccess,
        oauthExpiryEpochMs: newExpiry,
        oauthIdToken: newIdToken ?? account.oauthIdToken,
      );
      await replaceAccount(account, updated);
      debugPrint('[oauth] refresh success; expiresIn=${expiresIn}s');
      return updated;
    } catch (e) {
      debugPrint('[oauth] refresh exception: $e');
      return account;
    }
  }
}
