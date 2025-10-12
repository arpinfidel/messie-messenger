import 'package:flutter/material.dart';
import '../../../components/card.dart';
import '../../../components/segmented_control.dart';
import '../../../components/button.dart';
import '../../../components/chip.dart';

enum ConnectMethod { qr, pairing }

class ProviderDetailPage extends StatefulWidget {
  final String provider;
  const ProviderDetailPage({super.key, required this.provider});

  @override
  State<ProviderDetailPage> createState() => _ProviderDetailPageState();
}

class _ProviderDetailPageState extends State<ProviderDetailPage> {
  ConnectMethod _method = ConnectMethod.qr;
  MessieStatus _status = MessieStatus.notConnected;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.provider}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Status & Actions
          MessieCard(
            child: Row(
              children: [
                MessieStatusChip(status: _status),
                const Spacer(),
                if (_status == MessieStatus.connected)
                  MessieButton(
                    variant: MessieButtonVariant.secondary,
                    onPressed: () => setState(() => _status = MessieStatus.notConnected),
                    child: const Text('Disconnect'),
                  )
                else
                  MessieButton(
                    onPressed: () => setState(() => _status = MessieStatus.pending),
                    child: const Text('Connect'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 2. Connect Methods
          MessieCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Connect Methods', style: text.titleMedium),
                const SizedBox(height: 12),
                MessieSegmentedControl<ConnectMethod>(
                  value: _method,
                  segments: const [ConnectMethod.qr, ConnectMethod.pairing],
                  labelBuilder: (m) => Text(m == ConnectMethod.qr ? 'QR' : 'Pairing code'),
                  onChanged: (m) => setState(() => _method = m),
                ),
                const SizedBox(height: 12),
                if (_method == ConnectMethod.qr)
                  Container(
                    height: 220,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.qr_code_2, size: 120),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(
                      'ABCD-1234',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 20),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 3. Troubleshooting
          MessieCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Troubleshooting', style: text.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'If QR fails, try switching to Pairing code. Ensure your bridge is reachable and time is synchronized.',
                  style: text.bodySmall,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {},
                  child: const Text('Get help'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

