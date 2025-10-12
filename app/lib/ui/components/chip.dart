import 'package:flutter/material.dart';

enum MessieStatus { connected, notConnected, pending, error }

class MessieStatusChip extends StatelessWidget {
  final MessieStatus status;
  const MessieStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color bg;
    Color fg;
    String label;
    switch (status) {
      case MessieStatus.connected:
        bg = scheme.primaryContainer;
        fg = scheme.onPrimaryContainer;
        label = 'Connected';
      case MessieStatus.notConnected:
        bg = scheme.surfaceContainerHighest;
        fg = scheme.onSurfaceVariant;
        label = 'Not connected';
      case MessieStatus.pending:
        bg = scheme.tertiaryContainer;
        fg = scheme.onTertiaryContainer;
        label = 'Pending';
      case MessieStatus.error:
        bg = scheme.errorContainer;
        fg = scheme.onErrorContainer;
        label = 'Error';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg)),
    );
  }
}

