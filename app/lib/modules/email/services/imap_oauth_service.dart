import 'dart:io' show Platform;
import 'dart:convert';

import 'package:flutter_appauth/flutter_appauth.dart';

import '../../../api/imap_oauth.dart';
import 'email_account.dart';

class ImapOAuthService {
  final FlutterAppAuth _auth = const FlutterAppAuth();

  Future<List<ImapOAuthProviderConfig>> listProviders() async {
    final cfg = await ImapOAuthConfig.load();
    return cfg.providers;
  }

  Future<EmailAccountConfig?> signInWith(String providerId) async {
    final providers = await listProviders();
    final p = providers.firstWhere((e) => e.id == providerId, orElse: () => throw StateError('Provider not found'));
    if (p.androidClientId.isEmpty && p.iosClientId.isEmpty) return null;
    final clientId = Platform.isIOS ? p.iosClientId : p.androidClientId;
    AuthorizationTokenRequest req;
    if (p.authorizationEndpoint != null && p.tokenEndpoint != null) {
      final service = AuthorizationServiceConfiguration(
        authorizationEndpoint: p.authorizationEndpoint!,
        tokenEndpoint: p.tokenEndpoint!,
      );
      req = AuthorizationTokenRequest(
        clientId,
        p.redirectUri,
        serviceConfiguration: service,
        scopes: p.scopes,
        promptValues: const ['consent'],
      );
    } else {
      req = AuthorizationTokenRequest(
        clientId,
        p.redirectUri,
        issuer: p.issuer,
        scopes: p.scopes,
        promptValues: const ['consent'],
      );
    }

    final resp = await _auth.authorizeAndExchangeCode(req);
    if (resp == null || resp.accessToken == null) return null;

    final email = _emailFromIdToken(resp.idToken) ?? '';
    return EmailAccountConfig(
      label: email.isNotEmpty ? email : p.label,
      email: email,
      imapHost: p.imapHost,
      imapPort: p.imapPort,
      imapSecure: p.imapSecure,
      username: email.isNotEmpty ? email : clientId,
      password: '',
      smtpHost: p.smtpHost,
      smtpPort: p.smtpPort,
      smtpSecure: p.smtpSecure,
      authType: 'oauth2',
      provider: p.id,
      oauthAccessToken: resp.accessToken,
      oauthRefreshToken: resp.refreshToken,
      oauthExpiryEpochMs: resp.accessTokenExpirationDateTime?.millisecondsSinceEpoch,
      oauthIdToken: resp.idToken,
    );
  }

  String? _emailFromIdToken(String? idToken) {
    if (idToken == null) return null;
    try {
      final parts = idToken.split('.');
      if (parts.length < 2) return null;
      final b64 = parts[1];
      var out = b64;
      final mod = out.length % 4;
      if (mod != 0) out += '=' * (4 - mod);
      out = out.replaceAll('-', '+').replaceAll('_', '/');
      final payload = String.fromCharCodes(base64Decode(out));
      final m = jsonDecode(payload) as Map<String, dynamic>;
      return m['email'] as String?;
    } catch (_) {
      return null;
    }
  }
}
