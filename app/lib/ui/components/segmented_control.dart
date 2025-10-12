import 'package:flutter/material.dart';

class MessieSegmentedControl<T> extends StatelessWidget {
  final T value;
  final List<T> segments;
  final Widget Function(T) labelBuilder;
  final ValueChanged<T> onChanged;

  const MessieSegmentedControl({
    super.key,
    required this.value,
    required this.segments,
    required this.labelBuilder,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in segments)
          Padding(
            padding: const EdgeInsets.all(4),
            child: ChoiceChip(
              selected: value == s,
              onSelected: (_) => onChanged(s),
              label: labelBuilder(s),
              selectedColor: scheme.primaryContainer,
              showCheckmark: false,
              side: BorderSide(color: scheme.outlineVariant),
              labelStyle: Theme.of(context).textTheme.labelSmall,
            ),
          ),
      ],
    );
  }
}
