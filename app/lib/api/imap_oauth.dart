import 'dart:convert';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart' show loadYaml, YamlList, YamlMap;

class ImapOAuthProviderConfig {
  ImapOAuthProviderConfig({
    required this.id,
    required this.label,
    required this.issuer,
    required this.androidClientId,
    required this.iosClientId,
    required this.redirectUri,
    required this.scopes,
    required this.imapHost,
    required this.imapPort,
    required this.imapSecure,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpSecure,
    this.authorizationEndpoint,
    this.tokenEndpoint,
    this.useLoopback = false,
    this.loopbackHost = '127.0.0.1',
    this.loopbackPath = '/oauth2redirect',
    this.loopbackPort = 53219,
    this.clientSecret,
  });

  final String id;
  final String label;
  final String issuer;
  final String? authorizationEndpoint; // optional if discovery is used
  final String? tokenEndpoint; // optional if discovery is used
  final String androidClientId;
  final String iosClientId;
  final String redirectUri;
  final List<String> scopes;
  final String imapHost;
  final int imapPort;
  final bool imapSecure;
  final String smtpHost;
  final int smtpPort;
  final bool smtpSecure;
  final bool useLoopback; // if true, build dynamic http://{loopbackHost}:{port}{loopbackPath}
  final String loopbackHost;
  final String loopbackPath;
  final int loopbackPort;
  // Optional: for confidential (web) clients. Avoid shipping in production.
  final String? clientSecret;
}

class ImapOAuthConfig {
  ImapOAuthConfig(this.providers);
  final List<ImapOAuthProviderConfig> providers;

  static Future<ImapOAuthConfig> load() async {
    const envDefine = String.fromEnvironment('MESSIE_ENV', defaultValue: '');
    final env = envDefine.isNotEmpty ? envDefine : (kReleaseMode ? 'prod' : 'dev');
    final candidates = <String>[
      'assets/config/imap_oauth.local.yaml',
      'assets/config/imap_oauth.$env.yaml',
      'assets/config/imap_oauth.local.json',
      'assets/config/imap_oauth.$env.json',
    ];
    for (final path in candidates) {
      try {
        final raw = await rootBundle.loadString(path);
        final map = _decode(raw, path);
        final list = (map['providers'] as List?) ?? const [];
        final providers = list.map((e) => _toProvider(Map<String, dynamic>.from(e as Map))).toList();
        return ImapOAuthConfig(providers);
      } catch (_) {
        // keep trying
      }
    }
    return ImapOAuthConfig(const []);
  }

  static ImapOAuthProviderConfig _toProvider(Map<String, dynamic> m) {
    final imap = (m['imap'] as Map?)?.cast<String, dynamic>() ?? const {};
    final smtp = (m['smtp'] as Map?)?.cast<String, dynamic>() ?? const {};
    List<String> scopes = const [];
    final s = m['scopes'];
    if (s is List) scopes = s.cast<String>();
    return ImapOAuthProviderConfig(
      id: m['id'] as String,
      label: (m['label'] as String?) ?? m['id'] as String,
      issuer: (m['issuer'] as String?) ?? '',
      authorizationEndpoint: m['authorizationEndpoint'] as String?,
      tokenEndpoint: m['tokenEndpoint'] as String?,
      androidClientId: (m['androidClientId'] as String?) ?? '',
      iosClientId: (m['iosClientId'] as String?) ?? '',
      redirectUri: (m['redirectUri'] as String?) ?? '',
      scopes: scopes,
      imapHost: (imap['host'] as String?) ?? '',
      imapPort: (imap['port'] as num?)?.toInt() ?? 993,
      imapSecure: (imap['secure'] as bool?) ?? true,
      smtpHost: (smtp['host'] as String?) ?? '',
      smtpPort: (smtp['port'] as num?)?.toInt() ?? 587,
      smtpSecure: (smtp['secure'] as bool?) ?? true,
      useLoopback: (m['useLoopback'] as bool?) ?? false,
      loopbackHost: (m['loopbackHost'] as String?) ?? '127.0.0.1',
      loopbackPath: (m['loopbackPath'] as String?) ?? '/oauth2redirect',
      loopbackPort: (m['loopbackPort'] as num?)?.toInt() ?? 53219,
      clientSecret: m['clientSecret'] as String?,
    );
  }
}

Map<String, dynamic> _decode(String raw, String path) {
  if (path.endsWith('.json')) return jsonDecode(raw) as Map<String, dynamic>;
  final yaml = loadYaml(raw);
  dynamic convert(dynamic v) {
    if (v is YamlMap) {
      return Map<String, dynamic>.fromIterables(
        v.keys.map((k) => k.toString()),
        v.values.map(convert),
      );
    }
    if (v is YamlList) return v.map(convert).toList();
    return v;
  }
  final mapped = convert(yaml);
  return (mapped is Map<String, dynamic>) ? mapped : <String, dynamic>{};
}
