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
    this.oauthClientId,
    this.oauthTokenEndpoint,
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
  // Optional: persist exact OAuth client + token endpoint used to acquire the tokens.
  final String? oauthClientId;
  final String? oauthTokenEndpoint;

  EmailAccountConfig copyWith({
    String? label,
    String? email,
    String? imapHost,
    int? imapPort,
    bool? imapSecure,
    String? username,
    String? password,
    String? smtpHost,
    int? smtpPort,
    bool? smtpSecure,
    String? smtpUsername,
    String? smtpPassword,
    String? authType,
    String? provider,
    String? oauthAccessToken,
    String? oauthRefreshToken,
    int? oauthExpiryEpochMs,
    String? oauthIdToken,
    String? oauthClientId,
    String? oauthTokenEndpoint,
  }) {
    return EmailAccountConfig(
      label: label ?? this.label,
      email: email ?? this.email,
      imapHost: imapHost ?? this.imapHost,
      imapPort: imapPort ?? this.imapPort,
      imapSecure: imapSecure ?? this.imapSecure,
      username: username ?? this.username,
      password: password ?? this.password,
      smtpHost: smtpHost ?? this.smtpHost,
      smtpPort: smtpPort ?? this.smtpPort,
      smtpSecure: smtpSecure ?? this.smtpSecure,
      smtpUsername: smtpUsername ?? this.smtpUsername,
      smtpPassword: smtpPassword ?? this.smtpPassword,
      authType: authType ?? this.authType,
      provider: provider ?? this.provider,
      oauthAccessToken: oauthAccessToken ?? this.oauthAccessToken,
      oauthRefreshToken: oauthRefreshToken ?? this.oauthRefreshToken,
      oauthExpiryEpochMs: oauthExpiryEpochMs ?? this.oauthExpiryEpochMs,
      oauthIdToken: oauthIdToken ?? this.oauthIdToken,
      oauthClientId: oauthClientId ?? this.oauthClientId,
      oauthTokenEndpoint: oauthTokenEndpoint ?? this.oauthTokenEndpoint,
    );
  }

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
        'oauthClientId': oauthClientId,
        'oauthTokenEndpoint': oauthTokenEndpoint,
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
        oauthClientId: json['oauthClientId'] as String?,
        oauthTokenEndpoint: json['oauthTokenEndpoint'] as String?,
      );
}
