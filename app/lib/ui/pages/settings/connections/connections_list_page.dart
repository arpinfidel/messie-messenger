import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../components/card.dart';
import 'provider_connect_panel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:messie_app/modules/matrix/state/auth_view_model.dart';
import 'package:messie_app/services/bridges_service.dart';

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
          MessieCard(
            child: ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text('Email'),
              subtitle: const Text('Connect your email inbox'),
              trailing: _ConnectDropdown(
                label: 'Manage',
                options: const [
                  _ConnectOption(label: 'Manage accounts (soon)', value: 'manage', enabled: false),
                  _ConnectOption(label: 'Connect IMAP (soon)', value: 'imap', enabled: false),
                  _ConnectOption(label: 'Connect Gmail (soon)', value: 'gmail', enabled: false),
                ],
                onSelected: null,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
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
        color: enabled ? scheme.primary : scheme.surfaceVariant,
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
      if (accs.isEmpty) {
        final conns = await svc.listConnections();
        accs = conns.where((c) => (c['provider'] as String?) == 'whatsapp').toList();
      }
      if (!mounted) return;
      setState(() {
        _accounts = accs;
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
    final phone = a['phone'] ?? a['msisdn'] ?? a['user'] ?? a['id'];
    return phone?.toString() ?? 'Account';
  }

  String _statusForAccount(Map<String, dynamic> a) {
    final s = (a['status'] ?? a['state'] ?? a['connected'])?.toString();
    if (s == 'true') return 'connected';
    return s ?? '';
  }
}
