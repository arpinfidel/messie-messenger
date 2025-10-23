import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'matrix_sections.dart';
import 'email_sections.dart';
import 'todo_sections.dart';

typedef SettingsBuilder = Widget Function(BuildContext context, WidgetRef ref);

class SettingsSection {
  const SettingsSection({
    required this.id,
    required this.title,
    required this.builder,
    this.order = 0,
  });

  final String id;
  final String title;
  final SettingsBuilder builder;
  final int order;
}

/// Base provider to compose all module-contributed settings sections.
final settingsSectionsProvider = Provider<List<SettingsSection>>((ref) {
  final sections = <SettingsSection>[];
  // Matrix module (current app) sections
  sections.addAll(ref.watch(matrixModuleSettingsProvider));
  // Email module sections (placeholder)
  sections.addAll(ref.watch(emailModuleSettingsProvider));
  // To‑Do module sections (placeholder)
  sections.addAll(ref.watch(todoModuleSettingsProvider));
  sections.sort((a, b) => a.order.compareTo(b.order));
  return sections;
});

// Providers are defined in their respective modules (*_sections.dart)
