import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'provider_connect_panel.dart';

class ProviderDetailPage extends ConsumerWidget {
  final String provider;
  const ProviderDetailPage({super.key, required this.provider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text('Connect ${provider.toUpperCase()}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ProviderConnectPanel(provider: provider),
        ],
      ),
    );
  }
}
