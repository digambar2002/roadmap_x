import 'package:flutter/material.dart';
import '../../core/theme/colors.dart';

class GoalColorPicker extends StatelessWidget {
  final int selectedHex;
  final ValueChanged<int> onSelected;

  const GoalColorPicker({
    super.key,
    required this.selectedHex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: AppColors.goalColorHexes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final hex = AppColors.goalColorHexes[i];
          final color = Color(hex);
          final selected = selectedHex == hex;
          return GestureDetector(
            onTap: () => onSelected(hex),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(color: Colors.white, width: 2.5)
                    : null,
                boxShadow: selected
                    ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 8)]
                    : null,
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : null,
            ),
          );
        },
      ),
    );
  }
}
