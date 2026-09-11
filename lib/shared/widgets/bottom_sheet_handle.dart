import 'package:flutter/material.dart';

import '../../core/layout/adaptive_sheet.dart';

class BottomSheetHandle extends StatelessWidget {
  const BottomSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    // In a dialog there is nothing to drag, so the grab handle would be a
    // decoration that misrepresents how the surface behaves.
    if (AdaptiveSheetScope.isDialogOf(context)) {
      return const SizedBox(height: 8);
    }

    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: cs.outline,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
