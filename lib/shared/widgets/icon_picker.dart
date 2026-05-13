import 'package:flutter/material.dart';

const _emojis = [
  '🎯',
  '🚀',
  '💡',
  '📚',
  '💪',
  '🏆',
  '🌟',
  '🔥',
  '💻',
  '🎨',
  '🎵',
  '🏋️',
  '🧘',
  '🌱',
  '💼',
  '✈️',
  '🏠',
  '❤️',
  '🎓',
  '💰',
  '🌍',
  '🏃',
  '📝',
  '🔬',
  '🎮',
  '🎭',
  '🎪',
  '🎺',
  '⚽',
  '🏊',
  '🚴',
  '🧗',
  '🌺',
  '🦋',
  '🐉',
  '🌙',
  '⭐',
  '🌈',
  '🔮',
  '💎',
  '🧩',
  '🏔️',
  '🌊',
  '🦅',
  '🦁',
  '🦊',
  '🌻',
  '🍀',
  '⚡',
  '🛸',
];

class EmojiPickerWidget extends StatelessWidget {
  final String selectedEmoji;
  final ValueChanged<String> onSelected;

  const EmojiPickerWidget({
    super.key,
    required this.selectedEmoji,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 200,
      child: GridView.builder(
        padding: const EdgeInsets.all(4),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 52,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: _emojis.length,
        itemBuilder: (context, i) {
          final emoji = _emojis[i];
          final selected = selectedEmoji == emoji;
          return GestureDetector(
            onTap: () => onSelected(emoji),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color:
                    selected ? cs.primary.withOpacity(0.2) : cs.surfaceVariant,
                border:
                    selected ? Border.all(color: cs.primary, width: 1.5) : null,
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 24)),
            ),
          );
        },
      ),
    );
  }
}
