import 'package:flutter/material.dart';
import '../components/button.dart';
import '../components/chip.dart';

class ProviderListTile extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final MessieStatus status;
  final VoidCallback? onManage;
  final VoidCallback? onConnect;

  const ProviderListTile({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.status,
    this.onManage,
    this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final action = status == MessieStatus.connected
        ? MessieButton(
            variant: MessieButtonVariant.secondary,
            onPressed: onManage,
            child: const Text('Manage'),
          )
        : MessieButton(
            variant: MessieButtonVariant.primary,
            onPressed: onConnect,
            child: const Text('Connect'),
          );
    return ListTile(
      leading: leading,
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: action,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      subtitleTextStyle:
          Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      titleTextStyle:
          Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

