import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../components/card.dart';
import 'provider_connect_panel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:messie_app/modules/matrix/state/auth_view_model.dart';
import 'package:messie_app/services/bridges_service.dart';
import 'package:messie_app/modules/email/state/email_accounts_controller.dart';
import 'package:messie_app/modules/email/services/email_account.dart';
import 'package:messie_app/api/google_oauth.dart';
import 'package:messie_app/api/imap_oauth.dart';
import 'package:messie_app/modules/email/services/imap_oauth_service.dart';

class ConnectionsListPage extends StatelessWidget {
  const ConnectionsListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connections')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _ExpandableProviderCard(
            icon: Icons.chat_bubble_outline,
            title: 'WhatsApp',
            subtitle: 'Bridge your WhatsApp account',
            child: _WhatsAppAccountsPanel(),
          ),
          const SizedBox(height: 12),
          const _ExpandableProviderCard(
            icon: Icons.email_outlined,
            title: 'Email',
            subtitle: 'Connect your email inbox',
            child: _EmailAccountsPanel(),
          ),
        ],
      ),
    );
  }
}

class _ConnectOption {
  final String label;
  final String value;
  final bool enabled;
  const _ConnectOption({required this.label, required this.value, this.enabled = true});
}

class _ConnectDropdown extends StatelessWidget {
  final String label;
  final List<_ConnectOption> options;
  final ValueChanged<String?>? onSelected;
  const _ConnectDropdown({required this.label, required this.options, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final enabled = onSelected != null && options.any((o) => o.enabled);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: enabled ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: null,
          icon: Icon(Icons.arrow_drop_down_rounded, color: enabled ? scheme.onPrimary : scheme.onSurfaceVariant),
          hint: Row(
            children: [
              Icon(Icons.link_rounded, size: 18, color: enabled ? scheme.onPrimary : scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(color: enabled ? scheme.onPrimary : scheme.onSurfaceVariant),
              ),
            ],
          ),
          items: [
            for (final o in options)
              DropdownMenuItem<String>(
                value: o.value,
                enabled: o.enabled,
                child: Text(o.label),
              ),
          ],
          onChanged: enabled ? (v) => onSelected?.call(v) : null,
        ),
      ),
    );
  }
}

class _ExpandableProviderCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  const _ExpandableProviderCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  State<_ExpandableProviderCard> createState() => _ExpandableProviderCardState();
}

class _ExpandableProviderCardState extends State<_ExpandableProviderCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return MessieCard(
      child: Column(
        children: [
          ListTile(
            leading: Icon(widget.icon),
            title: Text(widget.title),
            subtitle: Text(widget.subtitle),
            trailing: Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded),
            onTap: () => setState(() => _expanded = !_expanded),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: widget.child,
            ),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

class _WhatsAppAccountsPanel extends ConsumerStatefulWidget {
  const _WhatsAppAccountsPanel();

  @override
  ConsumerState<_WhatsAppAccountsPanel> createState() => _WhatsAppAccountsPanelState();
}

class _WhatsAppAccountsPanelState extends ConsumerState<_WhatsAppAccountsPanel> {
  static const int _maxAccounts = 1; // expand later
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _accounts = const [];
  Map<String, dynamic>? _limits; // from /connections (backend-computed)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final jwt = ref.read(authControllerProvider).asData?.value?.backendJwt;
      final svc = BridgesService(bearerToken: jwt);
      // Prefer whoami for precise logins; fallback to listConnections
      final who = await svc.whoami(provider: 'whatsapp');
      final logins = (who['logins'] as List?)?.cast<Map>() ?? const [];
      List<Map<String, dynamic>> accs = logins.map((e) => Map<String, dynamic>.from(e)).toList();
      Map<String, dynamic>? limits;
      // Always query provider-level connection to get backend-computed limits/counts
      try {
        final conns = await svc.listConnections();
        final wa = conns.firstWhere(
          (c) => (c['provider'] as String?) == 'whatsapp',
          orElse: () => const {},
        );
        final l = (wa['limits'] as Map?);
        if (l != null) limits = l.cast<String, dynamic>();
      } catch (_) {
        // ignore; keep limits null
      }
      if (!mounted) return;
      setState(() {
        _accounts = accs;
        _limits = limits;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Failed to load accounts: $_error'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      );
    }

    int asInt(dynamic v, int fallback) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return fallback;
    }
    final maxFromBackend = asInt(_limits?['max_accounts'], _maxAccounts);
    final connectedCount = asInt(_limits?['connected_count'], _accounts.length);
    final canAdd = connectedCount < maxFromBackend;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_accounts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No accounts connected', style: Theme.of(context).textTheme.bodyMedium),
          ),
        for (final a in _accounts)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 0),
            leading: const Icon(Icons.account_circle_rounded),
            title: Text(_labelForAccount(a)),
            subtitle: Text(_statusForAccount(a)),
            trailing: TextButton(
              onPressed: () => context.push('/settings/connections/provider', extra: {'provider': 'whatsapp'}),
              child: const Text('Manage'),
            ),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: canAdd ? () => context.push('/settings/connections/provider', extra: {'provider': 'whatsapp'}) : null,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Connect new account'),
          ),
        ),
      ],
    );
  }

  String _labelForAccount(Map<String, dynamic> a) {
    // Try common fields, fallback to id
    final profile = (a['profile'] as Map?)?.cast<String, dynamic>();
    final name = a['name']?.toString();
    final displayName = profile?['displayName']?.toString();
    final externalId = profile?['externalId']?.toString();
    final phone = a['phone'] ?? a['msisdn'] ?? a['user'] ?? a['id'];
    return name ?? displayName ?? externalId ?? phone?.toString() ?? 'Account';
  }

  String _statusForAccount(Map<String, dynamic> a) {
    final s = (a['status'] ?? a['state'] ?? a['connected'])?.toString();
    if (s == 'true') return 'connected';
    return s ?? '';
  }
}

class _EmailAccountsPanel extends ConsumerStatefulWidget {
  const _EmailAccountsPanel();

  @override
  ConsumerState<_EmailAccountsPanel> createState() => _EmailAccountsPanelState();
}

class _EmailAccountsPanelState extends ConsumerState<_EmailAccountsPanel> {
  static const int _maxAccounts = 10;
  bool _loading = true;
  String? _error;
  List<EmailAccountConfig> _accounts = const [];
  bool _gmailEnabled = false;
  List<ImapOAuthProviderConfig> _oauthProviders = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _checkGmail();
    _loadImapProviders();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await ref.read(emailAccountsProvider.future);
      if (!mounted) return;
      setState(() { _accounts = list; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _checkGmail() async {
    final cfg = await GoogleOAuth.load();
    if (!mounted) return;
    setState(() { _gmailEnabled = cfg.isConfigured; });
  }

  Future<void> _loadImapProviders() async {
    final list = await ImapOAuthService().listProviders();
    if (!mounted) return;
    setState(() { _oauthProviders = list; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Failed to load accounts: $_error'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      );
    }

    final canAdd = _accounts.length < _maxAccounts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_accounts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No accounts connected', style: Theme.of(context).textTheme.bodyMedium),
          ),
        for (final a in _accounts)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 0),
            leading: const Icon(Icons.alternate_email_rounded),
            title: Text(a.label),
            subtitle: Text(a.email),
            trailing: TextButton(
              onPressed: () => context.push('/settings/connections/email-setup'),
              child: const Text('Manage'),
            ),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: _ConnectDropdown(
            label: 'Connect',
            options: const [
              _ConnectOption(label: 'IMAP', value: 'imap'),
              _ConnectOption(label: 'Gmail (OAuth)', value: 'gmail'),
            ],
            onSelected: (v) => _onConnectSelected(context, v),
          ),
        ),
        if (!canAdd)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Account limit reached', style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }

  void _onConnectSelected(BuildContext context, String? v) async {
    if (v == 'imap') {
      // Ask for auth method
      final method = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Choose IMAP auth method')),
              ListTile(
                leading: const Icon(Icons.password_rounded),
                title: const Text('Username / Password (app password)'),
                onTap: () => Navigator.of(ctx).pop('basic'),
              ),
              ListTile(
                enabled: _oauthProviders.isNotEmpty,
                leading: const Icon(Icons.verified_user_rounded),
                title: const Text('OAuth2'),
                onTap: () => Navigator.of(ctx).pop('oauth2'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (method == 'basic') {
        if (!context.mounted) return;
        context.push('/settings/connections/email-setup');
      } else if (method == 'oauth2') {
        if (!context.mounted) return;
        // Choose provider
        final providerId = await showModalBottomSheet<String>(
          context: context,
          builder: (ctx) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(title: Text('Choose provider')),
                for (final p in _oauthProviders)
                  ListTile(
                    title: Text(p.label),
                    subtitle: Text(p.issuer),
                    onTap: () => Navigator.of(ctx).pop(p.id),
                  ),
              ],
            ),
          ),
        );
        if (providerId == null) return;
        if (!context.mounted) return;
        context.push('/settings/connections/email-imap-oauth/$providerId');
      }
    } else if (v == 'gmail') {
      if (!_gmailEnabled) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gmail sign-in not configured')),
        );
        return;
      }
      if (!context.mounted) return;
      context.push('/settings/connections/email-gmail');
    }
  }
}
