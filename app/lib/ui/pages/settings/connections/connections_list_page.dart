import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../components/card.dart';
import '../../../components/list_tile.dart';
import '../../../components/chip.dart';

class ConnectionsListPage extends StatelessWidget {
  const ConnectionsListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connections')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MessieCard(
            child: ProviderListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: 'WhatsApp',
              subtitle: 'Bridge your WhatsApp account',
              status: MessieStatus.notConnected,
              onConnect: () => context.push('/settings/connections/provider', extra: 'whatsapp'),
            ),
          ),
          const SizedBox(height: 12),
          MessieCard(
            child: ProviderListTile(
              leading: const Icon(Icons.email_outlined),
              title: 'Email',
              subtitle: 'Connect your email inbox',
              status: MessieStatus.pending,
              onManage: () => context.push('/settings/connections/provider', extra: 'email'),
            ),
          ),
        ],
      ),
    );
  }
}
