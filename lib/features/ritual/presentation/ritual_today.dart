import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/services/shared_preferences_provider.dart';
import '../../../shared/widgets/animated_checkbox.dart';
import '../../analytics/providers/activity_provider.dart';
import '../../tasks/data/task_repository.dart';
import '../../tasks/providers/task_provider.dart';
import '../data/day_journal.dart';
import 'ritual_sheets.dart';

/// Today's top 3, as tasks, kept fresh as tasks change.
final todayTopTasksProvider = FutureProvider<List<Task>>((ref) async {
  ref.watch(taskChangesProvider);
  ref.watch(activityTickProvider);
  final now = DateTime.now();
  final uids = ref.watch(dayJournalProvider).topFor(now);
  if (uids.isEmpty) return const [];
  return TaskRepository.instance.getByUids(uids);
});

enum RitualKind { plan, wrapUp }

/// Which ritual Today should offer right now, if any. Mornings (until 2 pm)
/// offer planning; evenings (from 6 pm) offer the wrap-up.
RitualKind? ritualDue(DayJournal journal, DateTime now) {
  if (now.hour < 14 && !journal.hasPlanned(now)) return RitualKind.plan;
  if (now.hour >= 18 && !journal.hasWrappedUp(now)) return RitualKind.wrapUp;
  return null;
}

/// The morning/evening prompt at the top of Today. Dismissing hides it for
/// the rest of the day.
class RitualBanner extends ConsumerStatefulWidget {
  const RitualBanner({super.key, this.now});

  /// For tests.
  final DateTime? now;

  @override
  ConsumerState<RitualBanner> createState() => _RitualBannerState();
}

class _RitualBannerState extends ConsumerState<RitualBanner> {
  static String _dismissKey(RitualKind k) => 'ritual_dismissed_${k.name}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final now = widget.now ?? DateTime.now();
    final journal = ref.watch(dayJournalProvider);
    final kind = ritualDue(journal, now);
    if (kind == null) return const SizedBox.shrink();

    final prefs = ref.watch(sharedPreferencesProvider);
    final today = DayJournal.dayKey(now);
    if (prefs.getString(_dismissKey(kind)) == today) {
      return const SizedBox.shrink();
    }

    final plan = kind == RitualKind.plan;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: (plan ? const Color(0xFFF59E0B) : const Color(0xFF6366F1))
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () =>
              plan ? showPlanDaySheet(context) : showWrapUpSheet(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
            child: Row(
              children: [
                Text(plan ? '☀️' : '🌙', style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan ? 'Plan your day' : 'Wrap up your day',
                        style: tt.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        plan
                            ? 'Pick your top 3. Takes 2 minutes.'
                            : 'Roll unfinished tasks forward and note how it went.',
                        style:
                            tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Not today',
                  icon: Icon(Icons.close_rounded,
                      size: 18, color: cs.onSurfaceVariant),
                  onPressed: () async {
                    await prefs.setString(_dismissKey(kind), today);
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Today's top 3": the tasks picked in the morning plan, at the top of the
/// day so they can't get lost among everything else.
class TopThreeSection extends ConsumerWidget {
  const TopThreeSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final tasks =
        ref.watch(todayTopTasksProvider).valueOrNull ?? const <Task>[];
    if (tasks.isEmpty) return const SizedBox.shrink();
    final done = tasks.where((t) => t.isCompleted).length;
    final allDone = done == tasks.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: allDone
                ? const Color(0xFF10B981).withValues(alpha: 0.5)
                : cs.primary.withValues(alpha: 0.35),
          ),
          color: cs.primary.withValues(alpha: 0.05),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  allDone ? '🎉 Top 3 done' : "Today's top 3",
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Text('$done/${tasks.length}',
                    style:
                        tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                const Spacer(),
                TextButton(
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  onPressed: () => showPlanDaySheet(context),
                  child: const Text('Change'),
                ),
              ],
            ),
            for (var i = 0; i < tasks.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    AnimatedCheckbox(
                      checked: tasks[i].isCompleted,
                      color: cs.primary,
                      size: 22,
                      onToggle: () async {
                        HapticFeedback.lightImpact();
                        await TaskRepository.instance
                            .toggleComplete(tasks[i].id);
                        if (ref.context.mounted) bumpActivityTick(ref);
                      },
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tasks[i].text,
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: tasks[i].isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                          color:
                              tasks[i].isCompleted ? cs.onSurfaceVariant : null,
                        ),
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
