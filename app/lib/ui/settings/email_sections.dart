import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/messie_tokens.dart';
import 'settings_registry.dart';

final emailModuleSettingsProvider = Provider<List<SettingsSection>>((ref) {
  return <SettingsSection>[
    SettingsSection(
      id: 'email.general',
      title: 'Email',
      order: 30,
      builder: _buildEmailSection,
    ),
  ];
});

Widget _buildEmailSection(BuildContext context, WidgetRef ref) {
  final spacing = MessieSpacing.of(context);
  final textTheme = Theme.of(context).textTheme;
  final colors = Theme.of(context).colorScheme;
  return Card(
    child: Padding(
      padding: EdgeInsets.all(spacing.gap.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Email', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: spacing.gap.sm),
          Text(
            'Email accounts and preferences will appear here.',
            style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          SizedBox(height: spacing.gap.md),
          Row(
            children: [
              FilledButton.icon(
                onPressed: null, // TODO: navigate to email account linking
                icon: const Icon(Icons.alternate_email_rounded),
                label: const Text('Connect Email (soon)'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

