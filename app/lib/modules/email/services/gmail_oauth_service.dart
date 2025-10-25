import 'dart:convert';
import 'dart:io' show Platform, HttpClient;

import 'package:flutter_appauth/flutter_appauth.dart';

import '../../../api/google_oauth.dart';
import 'email_account.dart';

class GmailOAuthService {
  final FlutterAppAuth _appAuth = const FlutterAppAuth();

  // Returns an EmailAccountConfig populated from Google OAuth.
  Future<EmailAccountConfig?> signIn() async {
    final cfg = await GoogleOAuth.load();
    if (!cfg.isConfigured) return null;
    final clientId = Platform.isIOS ? cfg.iosClientId : cfg.androidClientId;
    final AuthorizationTokenRequest req = AuthorizationTokenRequest(
      clientId,
      cfg.redirectUri,
      issuer: cfg.issuer,
      scopes: const [
        'openid',
        'email',
        // Full Gmail scope enables IMAP/SMTP via XOAUTH2
        'https://mail.google.com/',
      ],
      promptValues: ['consent'],
      allowInsecureConnections: false,
    );

    final AuthorizationTokenResponse? resp = await _appAuth.authorizeAndExchangeCode(req);
    if (resp == null || resp.accessToken == null) return null;

    String? email = resp.idToken != null ? _extractEmailFromIdToken(resp.idToken!) : null;
    // Fallback to UserInfo endpoint if id_token lacks email claim
    if ((email == null || email.isEmpty) && resp.accessToken != null) {
      try {
        final userEmail = await _fetchEmailFromUserInfo(resp.accessToken!);
        if (userEmail != null && userEmail.isNotEmpty) {
          email = userEmail;
        }
      } catch (_) {}
    }

    return EmailAccountConfig(
      label: email ?? 'Gmail',
      email: email ?? '',
      imapHost: 'imap.gmail.com',
      imapPort: 993,
      imapSecure: true,
      username: email ?? '',
      password: '',
      smtpHost: 'smtp.gmail.com',
      smtpPort: 587,
      smtpSecure: true,
      authType: 'oauth2',
      provider: 'gmail',
      oauthAccessToken: resp.accessToken,
      oauthRefreshToken: resp.refreshToken,
      oauthExpiryEpochMs: resp.accessTokenExpirationDateTime?.millisecondsSinceEpoch,
      oauthIdToken: resp.idToken,
    );
  }

  String? _extractEmailFromIdToken(String idToken) {
    try {
      final parts = idToken.split('.');
      if (parts.length < 2) return null;
      final payload = utf8.decode(base64Url.decode(_pad(parts[1])));
      final map = jsonDecode(payload) as Map<String, dynamic>;
      return map['email'] as String?;
    } catch (_) {
      return null;
    }
  }

  String _pad(String input) {
    var out = input;
    final mod = out.length % 4;
    if (mod != 0) {
      out += '=' * (4 - mod);
    }
    return out.replaceAll('-', '+').replaceAll('_', '/');
  }

  Future<String?> _fetchEmailFromUserInfo(String accessToken) async {
    try {
      final client = HttpClient();
      final uri = Uri.parse('https://openidconnect.googleapis.com/v1/userinfo');
      final req = await client.getUrl(uri);
      req.headers.set('Authorization', 'Bearer $accessToken');
      final res = await req.close();
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final map = jsonDecode(body) as Map<String, dynamic>;
        return map['email'] as String?;
      }
    } catch (_) {}
    return null;
  }
}
