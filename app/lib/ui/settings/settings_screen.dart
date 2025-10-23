import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/messie_tokens.dart';
import 'settings_registry.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = MessieSpacing.of(context);
    final gutter = MessieSpacing.gutter(context);
    final sections = ref.watch(settingsSectionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: EdgeInsets.all(gutter),
        children: [
          for (final section in sections) ...[
            section.builder(context, ref),
            SizedBox(height: spacing.gap.md),
          ],
        ],
      ),
    );
  }
}

