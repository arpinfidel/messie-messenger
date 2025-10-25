import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../modules/email/services/gmail_oauth_service.dart';
import '../../../../modules/email/state/email_accounts_controller.dart';
import '../../../../api/google_oauth.dart';

class EmailGmailConnectPage extends ConsumerStatefulWidget {
  const EmailGmailConnectPage({super.key});

  @override
  ConsumerState<EmailGmailConnectPage> createState() => _EmailGmailConnectPageState();
}

class _EmailGmailConnectPageState extends ConsumerState<EmailGmailConnectPage> {
  bool _busy = false;
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    GoogleOAuth.load().then((cfg) {
      if (!mounted) return;
      setState(() { _enabled = cfg.isConfigured; });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect Gmail')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Authorize Messie to access your Gmail via OAuth 2.0.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: (!_enabled || _busy) ? null : () async {
                setState(()=> _busy = true);
                try {
                  final cfg = await GmailOAuthService().signIn();
                  if (cfg == null) return;
                  await ref.read(emailAccountsControllerProvider).addAccount(cfg);
                  if (!mounted) return;
                  Navigator.of(context).pop(true);
                } finally {
                  if (mounted) setState(()=> _busy = false);
                }
              },
              icon: const Icon(Icons.login_rounded),
              label: Text(!_enabled ? 'Gmail not configured' : _busy ? 'Connecting…' : 'Connect with Google'),
            ),
            const SizedBox(height: 8),
            const Text('Ensure your OAuth client IDs and redirect URI are configured.'),
          ],
        ),
      ),
    );
  }
}

