import 'package:flutter/material.dart';

import '../domain/repeat_rule.dart';

/// "Doesn't repeat" plus each [RepeatRule], as chips.
class RepeatSelector extends StatelessWidget {
  const RepeatSelector(
      {super.key, required this.value, required this.onChanged});

  final RepeatRule? value;
  final ValueChanged<RepeatRule?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        ChoiceChip(
          label: const Text('Once'),
          selected: value == null,
          onSelected: (_) => onChanged(null),
        ),
        for (final rule in RepeatRule.values)
          ChoiceChip(
            avatar: value == rule
                ? null
                : const Icon(Icons.repeat_rounded, size: 16),
            label: Text(rule.label),
            selected: value == rule,
            onSelected: (_) => onChanged(rule),
          ),
      ],
    );
  }
}
