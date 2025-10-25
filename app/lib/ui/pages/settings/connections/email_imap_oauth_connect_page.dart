import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../api/imap_oauth.dart';
import '../../../../modules/email/state/email_accounts_controller.dart';
import '../../../../modules/email/services/email_account.dart';

class EmailImapOAuthConnectPage extends ConsumerStatefulWidget {
  final String providerId;
  const EmailImapOAuthConnectPage({super.key, required this.providerId});

  @override
  ConsumerState<EmailImapOAuthConnectPage> createState() => _EmailImapOAuthConnectPageState();
}

class _EmailImapOAuthConnectPageState extends ConsumerState<EmailImapOAuthConnectPage> {
  ImapOAuthProviderConfig? _provider;
  bool _loading = true;
  bool _exchanging = false;
  String? _error;
  String? _authUrl;

  late final String _codeVerifier;
  late final String _codeChallenge;
  late final String _state;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final provs = await ImapOAuthConfig.load();
      final p = provs.providers.firstWhere((e) => e.id == widget.providerId);
      _provider = p;
      _generatePkce();
      final authUrl = await _buildAuthUrl(p);
      _authUrl = authUrl;
      // Launch in system browser (Custom Tabs / default)
      final uri = Uri.parse(authUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      _error = 'Failed to start OAuth: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _generatePkce() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(64, (_) => rnd.nextInt(256));
    _codeVerifier = _base64urlNoPad(bytes);
    final digest = crypto.sha256.convert(utf8.encode(_codeVerifier));
    _codeChallenge = _base64urlNoPad(digest.bytes);
    _state = _base64urlNoPad(List<int>.generate(32, (_) => rnd.nextInt(256)));
  }

  Future<String> _buildAuthUrl(ImapOAuthProviderConfig p) async {
    String authEndpoint = p.authorizationEndpoint ?? '';
    String tokenEndpoint = p.tokenEndpoint ?? '';
    String? userInfoEndpoint;
    if (authEndpoint.isEmpty || tokenEndpoint.isEmpty) {
      // Try discovery
      final dio = Dio();
      final resp = await dio.get('${p.issuer}/.well-known/openid-configuration');
      authEndpoint = authEndpoint.isEmpty ? (resp.data['authorization_endpoint'] as String) : authEndpoint;
      tokenEndpoint = tokenEndpoint.isEmpty ? (resp.data['token_endpoint'] as String) : tokenEndpoint;
      _discoveredTokenEndpoint = tokenEndpoint;
      userInfoEndpoint = (resp.data['userinfo_endpoint'] as String?);
    } else {
      _discoveredTokenEndpoint = tokenEndpoint;
    }
    _discoveredUserInfoEndpoint = userInfoEndpoint;
    final clientId = p.androidClientId.isNotEmpty ? p.androidClientId : p.iosClientId;

    // Build redirect: loopback if configured, else static
    String redirectUri;
    if (p.useLoopback) {
      try {
        _server = await HttpServer.bind(InternetAddress.loopbackIPv4, p.loopbackPort);
      } catch (e) {
        setState(() { _error = 'Failed to bind loopback port ${p.loopbackPort}: $e'; });
        rethrow;
      }
      // Prefer explicit IPv4 to avoid IPv6 (::1) resolution issues with 'localhost'
      final host = (p.loopbackHost.isEmpty || p.loopbackHost == 'localhost') ? '127.0.0.1' : p.loopbackHost;
      redirectUri = 'http://${host}:${p.loopbackPort}${p.loopbackPath}';
      _currentRedirectUri = redirectUri;
      _listenLoopback();
    } else {
      redirectUri = p.redirectUri;
    }

    final params = {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': p.scopes.join(' '),
      'code_challenge': _codeChallenge,
      'code_challenge_method': 'S256',
      'state': _state,
    };
    final uri = Uri.parse(authEndpoint).replace(queryParameters: params);
    return uri.toString();
  }

  String _base64urlNoPad(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

  String? _discoveredTokenEndpoint;
  String? _discoveredUserInfoEndpoint;
  HttpServer? _server;
  String? _currentRedirectUri;

  void _listenLoopback() async {
    _server?.listen((HttpRequest req) async {
      final p = _provider;
      if (p == null) return;
      final pathOk = req.uri.path == p.loopbackPath ||
          (!p.loopbackPath.endsWith('/') && req.uri.path == '${p.loopbackPath}/');
      if (pathOk) {
        final code = req.uri.queryParameters['code'];
        final state = req.uri.queryParameters['state'];
        if (code != null && state == _state) {
          // Respond HTML
          req.response.statusCode = 200;
          req.response.headers.set('Content-Type', 'text/html');
          req.response.headers.set('Cache-Control', 'no-store');
          req.response.write('<html><body><h3>Login successful. You can close this window.</h3></body></html>');
          await req.response.close();
          await _server?.close(force: true);
          _server = null;
          if (mounted) {
            // Exchange token
            await _exchangeCodeForToken(code);
          }
          return;
        }
        req.response.statusCode = 400;
        await req.response.close();
      } else {
        req.response.statusCode = 404;
        await req.response.close();
      }
    });
  }

  Future<void> _exchangeCodeForToken(String code) async {
    final p = _provider!;
    setState(() { _exchanging = true; _error = null; });
    final tokenEndpoint = _discoveredTokenEndpoint ?? p.tokenEndpoint!;
    final clientId = p.androidClientId.isNotEmpty ? p.androidClientId : p.iosClientId;
    final redirectUri = p.useLoopback
        ? (_currentRedirectUri ?? 'http://127.0.0.1:${p.loopbackPort}${p.loopbackPath}')
        : p.redirectUri;
    final dio = Dio();
    final form = {
      'grant_type': 'authorization_code',
      'client_id': clientId,
      'code': code,
      'redirect_uri': redirectUri,
      'code_verifier': _codeVerifier,
    };
    // Do NOT send client_secret by default for public (installed) clients using PKCE.
    // If the server explicitly complains that a client_secret is required and we have one,
    // retry once including it to support confidential/web client configs in dev.
    Future<Response<dynamic>> postToken(Map<String, dynamic> data) {
      return dio.post(
        tokenEndpoint,
        data: data,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.json,
          validateStatus: (status) => true,
        ),
      );
    }

    Response resp = await postToken(form);
    if (resp.statusCode != 200) {
      final body = resp.data;
      bool mentionsClientSecret = false;
      String msg;
      if (body is Map) {
        final err = (body['error'] ?? '').toString().toLowerCase();
        final desc = (body['error_description'] ?? body['errorSummary'] ?? '').toString().toLowerCase();
        mentionsClientSecret = desc.contains('client_secret') || desc.contains('client secret');
        mentionsClientSecret = mentionsClientSecret || err.contains('invalid_client') || err.contains('unauthorized_client');
        msg = (body['error_description'] ?? body['error'] ?? 'HTTP ${resp.statusCode}').toString();
      } else {
        msg = body?.toString() ?? 'HTTP ${resp.statusCode}';
      }
      if (mentionsClientSecret && (p.clientSecret != null && p.clientSecret!.isNotEmpty)) {
        final retryForm = Map<String, dynamic>.from(form);
        retryForm['client_secret'] = p.clientSecret!;
        resp = await postToken(retryForm);
      }
    }
    if (resp.statusCode != 200) {
      final body = resp.data;
      final msg = body is Map && body['error_description'] != null
          ? body['error_description'].toString()
          : body?.toString() ?? 'HTTP ${resp.statusCode}';
      setState(() { _error = 'Token exchange failed: $msg'; _exchanging = false; });
      return;
    }
    final data = resp.data as Map<String, dynamic>;
    final accessToken = data['access_token'] as String?;
    if (accessToken == null) {
      setState(() { _error = 'Token exchange failed (no access_token)'; _exchanging = false; });
      return;
    }
    final idToken = data['id_token'] as String?;
    String email = _emailFromIdToken(idToken) ?? '';
    if (email.isEmpty) {
      try {
        final fetched = await _emailFromUserInfo(accessToken);
        if (fetched != null && fetched.isNotEmpty) email = fetched;
      } catch (_) {}
    }
    if (email.isEmpty) {
      setState(() {
        _error = 'OAuth succeeded but no email address was returned.';
        _exchanging = false;
      });
      return;
    }
    final cfg = EmailAccountConfig(
      label: email.isNotEmpty ? email : p.label,
      email: email,
      imapHost: p.imapHost,
      imapPort: p.imapPort,
      imapSecure: p.imapSecure,
      // Gmail expects the email address as the username for IMAP XOAUTH2
      // IMAP XOAUTH2 username must be the email address for Gmail
      username: email,
      password: '',
      smtpHost: p.smtpHost,
      smtpPort: p.smtpPort,
      smtpSecure: p.smtpSecure,
      authType: 'oauth2',
      provider: p.id,
      oauthAccessToken: accessToken,
      oauthRefreshToken: data['refresh_token'] as String?,
      oauthExpiryEpochMs: DateTime.now().add(Duration(seconds: (data['expires_in'] as num?)?.toInt() ?? 3600)).millisecondsSinceEpoch,
      oauthIdToken: idToken,
      oauthClientId: clientId,
      oauthTokenEndpoint: tokenEndpoint,
    );
    await ref.read(emailAccountsControllerProvider).addAccount(cfg);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  String? _emailFromIdToken(String? idToken) {
    if (idToken == null) return null;
    try {
      final parts = idToken.split('.');
      if (parts.length < 2) return null;
      var b64 = parts[1];
      final mod = b64.length % 4;
      if (mod != 0) b64 += '=' * (4 - mod);
      final payload = utf8.decode(base64Url.decode(b64));
      final map = jsonDecode(payload) as Map<String, dynamic>;
      return map['email'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _emailFromUserInfo(String accessToken) async {
    try {
      final dio = Dio();
      final url = _discoveredUserInfoEndpoint ?? 'https://openidconnect.googleapis.com/v1/userinfo';
      final resp = await dio.get(
        url,
        options: Options(
          headers: {'Authorization': 'Bearer $accessToken'},
          validateStatus: (s) => true,
        ),
      );
      if (resp.statusCode == 200 && resp.data is Map) {
        final map = resp.data as Map;
        final email = map['email'] as String?;
        return email;
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = _provider;
    return Scaffold(
      appBar: AppBar(title: Text(p?.label ?? 'Connect Email')),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (p?.useLoopback == true)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text('Redirect: ${_currentRedirectUri ?? 'http://127.0.0.1:${p!.loopbackPort}${p.loopbackPath}'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('A secure browser has been opened. Complete sign-in there.\nIf the browser didn\'t open, tap the button below.'),
          ),
          FilledButton.icon(
            onPressed: (_authUrl == null) ? null : () async {
              final uri = Uri.parse(_authUrl!);
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            icon: const Icon(Icons.open_in_browser_rounded),
            label: const Text('Open in browser'),
          ),
        ],
      ),
    );
  }
}
