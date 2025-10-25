class EmailAccountConfig {
  EmailAccountConfig({
    required this.label,
    required this.email,
    required this.imapHost,
    required this.imapPort,
    required this.imapSecure,
    required this.username,
    this.password,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpSecure,
    String? smtpUsername,
    String? smtpPassword,
    this.authType = 'basic',
    this.provider,
    this.oauthAccessToken,
    this.oauthRefreshToken,
    this.oauthExpiryEpochMs,
    this.oauthIdToken,
  })  : smtpUsername = smtpUsername ?? username,
        smtpPassword = (smtpPassword ?? password ?? '');

  final String label;
  final String email;
  final String imapHost;
  final int imapPort;
  final bool imapSecure;
  final String username;
  final String? password;
  final String smtpHost;
  final int smtpPort;
  final bool smtpSecure;
  final String smtpUsername;
  final String smtpPassword;
  final String authType; // 'basic' | 'oauth2'
  final String? provider; // e.g., 'gmail'
  final String? oauthAccessToken;
  final String? oauthRefreshToken;
  final int? oauthExpiryEpochMs;
  final String? oauthIdToken;

  Map<String, dynamic> toJson() => {
        'label': label,
        'email': email,
        'imapHost': imapHost,
        'imapPort': imapPort,
        'imapSecure': imapSecure,
        'username': username,
        'password': password,
        'smtpHost': smtpHost,
        'smtpPort': smtpPort,
        'smtpSecure': smtpSecure,
        'smtpUsername': smtpUsername,
        'smtpPassword': smtpPassword,
        // Persist auth type and OAuth fields so IMAP can authenticate on reload.
        'authType': authType,
        'provider': provider,
        'oauthAccessToken': oauthAccessToken,
        'oauthRefreshToken': oauthRefreshToken,
        'oauthExpiryEpochMs': oauthExpiryEpochMs,
        'oauthIdToken': oauthIdToken,
      };

  static EmailAccountConfig fromJson(Map<String, dynamic> json) => EmailAccountConfig(
        label: (json['label'] as String?) ?? (json['email'] as String? ?? 'Email'),
        email: json['email'] as String,
        imapHost: json['imapHost'] as String,
        imapPort: (json['imapPort'] as num).toInt(),
        imapSecure: json['imapSecure'] as bool,
        username: json['username'] as String,
        password: json['password'] as String?,
        smtpHost: json['smtpHost'] as String,
        smtpPort: (json['smtpPort'] as num).toInt(),
        smtpSecure: json['smtpSecure'] as bool,
        smtpUsername: (json['smtpUsername'] as String?) ?? json['username'] as String,
        smtpPassword: (json['smtpPassword'] as String?) ?? (json['password'] as String? ?? ''),
        authType: (json['authType'] as String?) ?? 'basic',
        provider: json['provider'] as String?,
        oauthAccessToken: json['oauthAccessToken'] as String?,
        oauthRefreshToken: json['oauthRefreshToken'] as String?,
        oauthExpiryEpochMs: (json['oauthExpiryEpochMs'] as num?)?.toInt(),
        oauthIdToken: json['oauthIdToken'] as String?,
      );
}
