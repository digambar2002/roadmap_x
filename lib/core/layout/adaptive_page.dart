import 'package:flutter/material.dart';

import 'breakpoints.dart';

/// Centres a page's content and stops it stretching across a wide window.
///
/// Wrap the scrollable itself, not the Scaffold: the scroll view keeps the
/// full height (so its scrollbar sits where expected) while its contents stay
/// within a readable measure.
class AdaptivePage extends StatelessWidget {
  const AdaptivePage({
    super.key,
    required this.child,
    this.maxWidth = Breakpoints.readableMaxWidth,
  });

  /// Use [Breakpoints.wideMaxWidth] for screens that lay out columns.
  const AdaptivePage.wide({super.key, required this.child})
      : maxWidth = Breakpoints.wideMaxWidth;

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    // Narrow windows already have the right measure; adding a constraint there
    // only risks fighting the existing padding.
    if (context.isCompact) return child;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Lays children out in one column when narrow and side by side when wide.
///
/// [main] keeps the primary content; [side] is secondary and moves below the
/// main column on compact widths rather than disappearing.
class AdaptiveColumns extends StatelessWidget {
  const AdaptiveColumns({
    super.key,
    required this.main,
    required this.side,
    this.spacing = 24,
    this.sideFlex = 4,
    this.mainFlex = 6,
  });

  final Widget main;
  final Widget side;
  final double spacing;
  final int sideFlex;
  final int mainFlex;

  @override
  Widget build(BuildContext context) {
    if (!context.isExpanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [main, SizedBox(height: spacing), side],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: mainFlex, child: main),
        SizedBox(width: spacing),
        Expanded(flex: sideFlex, child: side),
      ],
    );
  }
}
