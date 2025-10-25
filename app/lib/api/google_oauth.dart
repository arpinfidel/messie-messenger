import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:yaml/yaml.dart' show loadYaml, YamlList, YamlMap;

class GoogleOAuthConfig {
  static const String issuer = String.fromEnvironment('GOOGLE_OAUTH_ISSUER', defaultValue: 'https://accounts.google.com');
  static const String androidClientId = String.fromEnvironment('GOOGLE_OAUTH_ANDROID_CLIENT_ID', defaultValue: 'YOUR_ANDROID_CLIENT_ID.apps.googleusercontent.com');
  static const String iosClientId = String.fromEnvironment('GOOGLE_OAUTH_IOS_CLIENT_ID', defaultValue: 'YOUR_IOS_CLIENT_ID.apps.googleusercontent.com');
  static const String redirectUri = String.fromEnvironment('GOOGLE_OAUTH_REDIRECT_URI', defaultValue: 'com.example.temp_flutter_template:/oauth2redirect');
}

class GoogleOAuth {
  GoogleOAuth({
    required this.issuer,
    required this.androidClientId,
    required this.iosClientId,
    required this.redirectUri,
  });

  final String issuer;
  final String androidClientId;
  final String iosClientId;
  final String redirectUri;

  static Future<GoogleOAuth> load() async {
    // Load from asset in assets/config with precedence: local > env > mode
    const envDefine = String.fromEnvironment('MESSIE_ENV', defaultValue: '');
    final env = envDefine.isNotEmpty ? envDefine : (kReleaseMode ? 'prod' : 'dev');
    final candidates = <String>[
      // YAML preferred
      'assets/config/google_oauth.local.yaml',
      'assets/config/google_oauth.$env.yaml',
      // JSON fallback
      'assets/config/google_oauth.local.json',
      'assets/config/google_oauth.$env.json',
    ];
    for (final path in candidates) {
      try {
        final raw = await rootBundle.loadString(path);
        final map = _decodeConfig(raw, path);
        return GoogleOAuth(
          issuer: (map['issuer'] as String?) ?? GoogleOAuthConfig.issuer,
          androidClientId: (map['androidClientId'] as String?) ?? GoogleOAuthConfig.androidClientId,
          iosClientId: (map['iosClientId'] as String?) ?? GoogleOAuthConfig.iosClientId,
          redirectUri: (map['redirectUri'] as String?) ?? GoogleOAuthConfig.redirectUri,
        );
      } catch (_) {
        // try next
      }
    }
    // Fallback to dart-defines
    return GoogleOAuth(
      issuer: GoogleOAuthConfig.issuer,
      androidClientId: GoogleOAuthConfig.androidClientId,
      iosClientId: GoogleOAuthConfig.iosClientId,
      redirectUri: GoogleOAuthConfig.redirectUri,
    );
  }

  bool get isConfigured =>
      !androidClientId.startsWith('YOUR_') && !iosClientId.startsWith('YOUR_') && redirectUri.contains(':/');
}

Map<String, dynamic> _decodeConfig(String raw, String path) {
  if (path.endsWith('.json')) {
    return jsonDecode(raw) as Map<String, dynamic>;
  }
  final yaml = loadYaml(raw);
  dynamic convert(dynamic v) {
    if (v is YamlMap) {
      return Map<String, dynamic>.fromIterables(
        v.keys.map((k) => k.toString()),
        v.values.map(convert),
      );
    }
    if (v is YamlList) {
      return v.map(convert).toList();
    }
    return v;
  }
  final mapped = convert(yaml);
  return (mapped is Map<String, dynamic>) ? mapped : <String, dynamic>{};
}
