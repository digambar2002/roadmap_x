import 'package:flutter/material.dart';

import '../../core/models/today_task.dart';

class DueDateBadge extends StatelessWidget {
  final TodayTaskContext contextData;

  const DueDateBadge({
    super.key,
    required this.contextData,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Color bg;
    Color fg;
    String label;

    if (contextData.isOverdue) {
      bg = const Color(0xFFF87171).withOpacity(0.15);
      fg = const Color(0xFFF87171);
      label = 'Overdue';
    } else if (contextData.isDueToday) {
      bg = const Color(0xFFFBBF24).withOpacity(0.2);
      fg = const Color(0xFFD97706);
      label = 'Today';
    } else if (contextData.isDueThisWeek) {
      bg = cs.primary.withOpacity(0.15);
      fg = cs.primary;
      label = 'This week';
    } else {
      bg = cs.surfaceVariant;
      fg = cs.onSurfaceVariant;
      label = 'Upcoming';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
