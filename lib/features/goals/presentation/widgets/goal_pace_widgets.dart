import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/services/shared_preferences_provider.dart';
import '../../domain/goal_pace.dart';
import '../../providers/goal_pace_provider.dart';

Color paceColor(PaceStatus s, ColorScheme cs) => switch (s) {
      PaceStatus.done || PaceStatus.ahead => const Color(0xFF10B981),
      PaceStatus.onTrack => cs.primary,
      PaceStatus.behind => const Color(0xFFF59E0B),
      PaceStatus.overdue => cs.error,
      PaceStatus.noTasks => cs.onSurfaceVariant,
    };

IconData paceIcon(PaceStatus s) => switch (s) {
      PaceStatus.done => Icons.emoji_events_outlined,
      PaceStatus.ahead => Icons.rocket_launch_outlined,
      PaceStatus.onTrack => Icons.trending_flat_rounded,
      PaceStatus.behind => Icons.speed_rounded,
      PaceStatus.overdue => Icons.event_busy_outlined,
      PaceStatus.noTasks => Icons.playlist_add_rounded,
    };

/// One line on a goal card: "On track · 2 tasks/week".
class GoalPaceLine extends ConsumerWidget {
  const GoalPaceLine({super.key, required this.goalId});
  final int goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pace = ref.watch(goalPaceProvider(goalId)).valueOrNull;
    if (pace == null) return const SizedBox(height: 16);
    final cs = Theme.of(context).colorScheme;
    final color = paceColor(pace.status, cs);
    return Row(
      children: [
        Icon(paceIcon(pace.status), size: 14, color: color),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            pace.summary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
        ),
      ],
    );
  }
}

/// On the goal page: time used against work done, side by side, and what
/// it takes to finish on time.
class GoalPaceCard extends ConsumerWidget {
  const GoalPaceCard(
      {super.key, required this.goalId, required this.targetDate});
  final int goalId;
  final DateTime targetDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pace = ref.watch(goalPaceProvider(goalId)).valueOrNull;
    if (pace == null || pace.status == PaceStatus.noTasks) {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = paceColor(pace.status, cs);

    Widget bar(String label, double value, Color c) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              SizedBox(width: 72, child: Text(label, style: tt.labelSmall)),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 8,
                    backgroundColor: cs.outline.withValues(alpha: 0.3),
                    valueColor: AlwaysStoppedAnimation(c),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 36,
                child: Text('${(value * 100).round()}%',
                    textAlign: TextAlign.end, style: tt.labelSmall),
              ),
            ],
          ),
        );

    final daysText = pace.daysLeft < 0
        ? '${-pace.daysLeft} days past ${DateFormat('d MMM').format(targetDate)}'
        : pace.daysLeft == 0
            ? 'Due today'
            : '${pace.daysLeft} days left · ${DateFormat('d MMM').format(targetDate)}';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(paceIcon(pace.status), size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  pace.summary,
                  style: tt.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(daysText,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          bar('Time used', pace.timeUsed, cs.onSurfaceVariant),
          bar('Work done', pace.progress, color),
        ],
      ),
    );
  }
}

/// On Today: the one goal that has sat untouched longest, with a nudge back.
class StaleGoalNudge extends ConsumerWidget {
  const StaleGoalNudge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stale = ref.watch(staleGoalProvider).valueOrNull;
    if (stale == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final g = stale.goal;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('💤', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No progress on ${g.emoji} ${g.name} in ${stale.pace.staleDays} days',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 2),
              child: Text(
                'One small task keeps it alive. ${stale.pace.summary}.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () async {
                    final until = DateTime.now()
                        .add(const Duration(days: staleSnoozeDays));
                    await ref.read(sharedPreferencesProvider).setString(
                        staleSnoozeKey(g.uid), until.toIso8601String());
                    ref.invalidate(staleGoalProvider);
                  },
                  child: const Text('Later'),
                ),
                FilledButton.tonal(
                  onPressed: () => context.push('/goals/${g.id}'),
                  child: const Text('Pick a task'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
