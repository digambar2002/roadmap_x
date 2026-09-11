import 'package:flutter/material.dart';
import '../../../core/layout/adaptive_sheet.dart';

Future<T?> showCoachBottomSheet<T>(
  BuildContext context,
  Widget child,
) {
  return showAdaptiveSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (ctx) {
      final height = MediaQuery.sizeOf(ctx).height * 0.88;
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: SizedBox(height: height, child: child),
      );
    },
  );
}
