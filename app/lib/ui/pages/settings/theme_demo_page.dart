import 'package:flutter/material.dart';
import '../../theme/colors.dart';
import '../../theme/theme.dart';
import '../../theme/accent_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ThemeDemoPage extends ConsumerStatefulWidget {
  const ThemeDemoPage({super.key});

  @override
  ConsumerState<ThemeDemoPage> createState() => _ThemeDemoPageState();
}

class _ThemeDemoPageState extends ConsumerState<ThemeDemoPage> {
  ThemeMode _mode = ThemeMode.system;

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(accentControllerProvider).maybeWhen(
          data: (a) => a,
          orElse: () => MessieAccent.aqua,
        );
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final b = switch (_mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => platformBrightness,
    };
    final theme = MessieThemeBuilder.build(
      brightness: b,
      accent: accent,
    );
    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(title: const Text('Theme Demo (OKLCH)')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Choose theme mode'),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 16),
            const Text('Choose accent'),
            const SizedBox(height: 8),
            SegmentedButton<MessieAccent>(
              segments: const [
                ButtonSegment(value: MessieAccent.aqua, label: Text('Aqua')),
                ButtonSegment(value: MessieAccent.peach, label: Text('Peach')),
                ButtonSegment(value: MessieAccent.violet, label: Text('Violet')),
                ButtonSegment(value: MessieAccent.slate, label: Text('Slate')),
              ],
              selected: {accent},
              onSelectionChanged: (s) {
                ref.read(accentControllerProvider.notifier).setAccent(s.first);
              },
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Preview', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: () {}, child: const Text('Primary')),
                    const SizedBox(height: 8),
                    OutlinedButton(onPressed: () {}, child: const Text('Secondary')),
                    const SizedBox(height: 8),
                    TextField(decoration: const InputDecoration(labelText: 'Input field')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Extending colors via OKLCH: define new accents by providing OKLCH parameters (l, c, h), then feed the converted sRGB color into ColorScheme.fromSeed. This ensures perceptually uniform steps across light/dark modes.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
