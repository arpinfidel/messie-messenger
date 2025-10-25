import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../modules/email/state/email_accounts_controller.dart';
import '../../../../modules/email/services/email_account.dart';
import '../../../../modules/email/services/gmail_oauth_service.dart';
import '../../../../api/google_oauth.dart';

class EmailSetupPage extends ConsumerStatefulWidget {
  const EmailSetupPage({super.key});

  @override
  ConsumerState<EmailSetupPage> createState() => _EmailSetupPageState();
}

class _EmailSetupPageState extends ConsumerState<EmailSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController(text: 'My Email');
  final _email = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _imapHost = TextEditingController();
  final _imapPort = TextEditingController(text: '993');
  bool _imapSecure = true;
  final _smtpHost = TextEditingController();
  final _smtpPort = TextEditingController(text: '587');
  bool _smtpSecure = true;
  bool _saving = false;
  bool _busyGoogle = false;

  @override
  void dispose() {
    _label.dispose();
    _email.dispose();
    _user.dispose();
    _pass.dispose();
    _imapHost.dispose();
    _imapPort.dispose();
    _smtpHost.dispose();
    _smtpPort.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect Email')), 
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Connect with IMAP/SMTP', style: Theme.of(context).textTheme.titleMedium),
              TextFormField(controller: _label, decoration: const InputDecoration(labelText: 'Account label')),            
              TextFormField(controller: _email, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress, validator: (v) => (v==null||v.isEmpty)?'Required':null),
              const SizedBox(height: 12),
              const Text('IMAP', style: TextStyle(fontWeight: FontWeight.w600)),
              TextFormField(controller: _imapHost, decoration: const InputDecoration(labelText: 'IMAP host'), validator: (v)=> (v==null||v.isEmpty)?'Required':null),
              TextFormField(controller: _imapPort, decoration: const InputDecoration(labelText: 'IMAP port'), keyboardType: TextInputType.number),
              SwitchListTile(value: _imapSecure, onChanged: (v)=> setState(()=>_imapSecure=v), title: const Text('IMAPS (TLS)')),
              TextFormField(controller: _user, decoration: const InputDecoration(labelText: 'IMAP username'), validator: (v)=> (v==null||v.isEmpty)?'Required':null),
              TextFormField(controller: _pass, decoration: const InputDecoration(labelText: 'IMAP password / app password'), obscureText: true, validator: (v)=> (v==null||v.isEmpty)?'Required':null),
              const SizedBox(height: 12),
              const Text('SMTP', style: TextStyle(fontWeight: FontWeight.w600)),
              TextFormField(controller: _smtpHost, decoration: const InputDecoration(labelText: 'SMTP host'), validator: (v)=> (v==null||v.isEmpty)?'Required':null),
              TextFormField(controller: _smtpPort, decoration: const InputDecoration(labelText: 'SMTP port'), keyboardType: TextInputType.number),
              SwitchListTile(value: _smtpSecure, onChanged: (v)=> setState(()=>_smtpSecure=v), title: const Text('SMTPS (TLS)')),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : () async {
                  if (!_formKey.currentState!.validate()) return;
                  setState(()=> _saving = true);
                  final cfg = EmailAccountConfig(
                    label: _label.text.trim().isEmpty ? _email.text.trim() : _label.text.trim(),
                    email: _email.text.trim(),
                    imapHost: _imapHost.text.trim(),
                    imapPort: int.tryParse(_imapPort.text.trim()) ?? 993,
                    imapSecure: _imapSecure,
                    username: _user.text.trim(),
                    password: _pass.text,
                    smtpHost: _smtpHost.text.trim(),
                    smtpPort: int.tryParse(_smtpPort.text.trim()) ?? 587,
                    smtpSecure: _smtpSecure,
                  );
                  try {
                    await ref.read(emailAccountsControllerProvider).addAccount(cfg);
                    if (!mounted) return;
                    Navigator.of(context).pop(true);
                  } finally {
                    if (mounted) setState(()=> _saving = false);
                  }
                },
                child: Text(_saving ? 'Saving…' : 'Save account'),
              )
              ,
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 12),
              Text('Or sign in with Google (Gmail)', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: (_busyGoogle || _googleDisabled()) ? null : () async {
                  setState(()=> _busyGoogle = true);
                  try {
                    final cfg = await GmailOAuthService().signIn();
                    if (cfg == null) return;
                    await ref.read(emailAccountsControllerProvider).addAccount(cfg);
                    if (!mounted) return;
                    Navigator.of(context).pop(true);
                  } finally {
                    if (mounted) setState(()=> _busyGoogle = false);
                  }
                },
                icon: const Icon(Icons.login_rounded),
                label: Text(_busyGoogle ? 'Signing in…' : _googleDisabled() ? 'Google sign-in not configured' : 'Sign in with Google'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _googleDisabled() {
    final hasClient = !(GoogleOAuthConfig.androidClientId.startsWith('YOUR_') && GoogleOAuthConfig.iosClientId.startsWith('YOUR_'));
    final redirectOk = !GoogleOAuthConfig.redirectUri.contains('example');
    return !(hasClient && redirectOk);
  }
}
