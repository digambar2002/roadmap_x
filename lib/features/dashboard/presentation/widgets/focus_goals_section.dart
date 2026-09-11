import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/models.dart';
import '../../providers/dashboard_provider.dart';

/// Goals on the dashboard, led by the ones marked Focus.
///
/// The old version rendered every active goal as a horizontally scrolling
/// carousel, which made ten goals look exactly as urgent as one. Here only
/// Focus goals get room; everything else collapses to a single count, so the
/// dashboard stays a short list of what to do rather than a long list of what
/// is outstanding.
class FocusGoalsSection extends StatelessWidget {
  const FocusGoalsSection({super.key, required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final focus =
        data.goals.where((g) => g.priority == GoalPriority.focus).toList();
    final active =
        data.goals.where((g) => g.priority == GoalPriority.active).toList();
    final someday =
        data.goals.where((g) => g.priority == GoalPriority.someday).toList();

    // Nothing marked Focus yet: fall back to the first few active goals rather
    // than showing an empty section, and say how to change that.
    final leading = focus.isNotEmpty ? focus : active.take(3).toList();
    final remaining = data.goals.length - leading.length;

    if (data.goals.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                focus.isNotEmpty ? 'Focus' : 'Your goals',
                style: tt.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            TextButton(
              onPressed: () => context.go('/goals'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('All goals'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final goal in leading)
          _GoalRow(
            goal: goal,
            percent: data.goalProgress[goal.id] ?? 0,
          ),
        if (focus.isEmpty && active.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Mark a goal as Focus when editing it to pin it here.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        if (remaining > 0) ...[
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => context.go('/goals'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(
                children: [
                  Icon(Icons.more_horiz_rounded,
                      size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    _remainingLabel(remaining, someday.length),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _remainingLabel(int remaining, int someday) {
    final plural = remaining == 1 ? 'goal' : 'goals';
    if (someday == 0) return '$remaining more $plural';
    return '$remaining more $plural · $someday on Someday';
  }
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({required this.goal, required this.percent});

  final Goal goal;
  final double percent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = Color(goal.colorHex);
    final pct = (percent * 100).round();

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('/goals/${goal.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Text(goal.emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          goal.name,
                          style: tt.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$pct%',
                        style: tt.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: percent.clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor: cs.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
