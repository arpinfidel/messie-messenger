import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/messie_tokens.dart';
import 'settings_registry.dart';

final todoModuleSettingsProvider = Provider<List<SettingsSection>>((ref) {
  return <SettingsSection>[
    SettingsSection(
      id: 'todo.general',
      title: 'To‑Do',
      order: 40,
      builder: _buildTodoSection,
    ),
  ];
});

Widget _buildTodoSection(BuildContext context, WidgetRef ref) {
  final spacing = MessieSpacing.of(context);
  final textTheme = Theme.of(context).textTheme;
  final colors = Theme.of(context).colorScheme;
  return Card(
    child: Padding(
      padding: EdgeInsets.all(spacing.gap.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('To‑Do', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: spacing.gap.sm),
          Text(
            'Manage tasks and lists. Integration coming soon.',
            style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          SizedBox(height: spacing.gap.md),
          Row(
            children: [
              FilledButton.icon(
                onPressed: null, // TODO: navigate to to‑do preferences
                icon: const Icon(Icons.checklist_rounded),
                label: const Text('Configure To‑Do (soon)'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

