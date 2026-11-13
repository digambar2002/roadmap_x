import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/layout/adaptive_sheet.dart';
import '../../../core/models/today_task.dart';
import '../../../core/services/sound_service.dart';
import '../../analytics/providers/activity_provider.dart';
import '../../habits/providers/habit_provider.dart';
import '../../pet/domain/pet_domain.dart';
import '../../pet/providers/pet_provider.dart';
import '../../tasks/data/task_repository.dart';
import '../../tasks/providers/task_provider.dart';
import '../data/day_journal.dart';

const maxTopTasks = 3;

Future<void> showPlanDaySheet(BuildContext context) => showAdaptiveSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const PlanDaySheet(),
    );

Future<void> showWrapUpSheet(BuildContext context) => showAdaptiveSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const WrapUpSheet(),
    );

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// Commits the morning plan: picked tasks move to today and become the top 3.
Future<void> startDay(
  DayJournalNotifier journal, {
  required List<String> picked,
  required List<TodayTaskContext> candidates,
}) async {
  final today = _today();
  final byUid = {for (final c in candidates) c.task.uid: c};
  final move = [
    for (final uid in picked)
      if (byUid[uid] case final c? when !c.isDueToday) c.task.id,
  ];
  await TaskRepository.instance.setDueDates(move, today);
  await journal.setTop(today, picked);
}

/// Commits the evening wrap-up: rolls tasks to tomorrow and saves the note.
Future<void> wrapUpDay(
  DayJournalNotifier journal, {
  required int mood,
  required String note,
  required List<int> rollTaskIds,
}) async {
  final today = _today();
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  await TaskRepository.instance.setDueDates(rollTaskIds, tomorrow);
  await journal.saveNote(today, mood: mood, note: note);
}

// ── Morning: plan the day ─────────────────────────────────

/// Two minutes in the morning: pick up to three tasks that would make today
/// a good day. Picked tasks are moved to today, and show as "Today's top 3"
/// at the top of the Today tab.
class PlanDaySheet extends ConsumerStatefulWidget {
  const PlanDaySheet({super.key});

  @override
  ConsumerState<PlanDaySheet> createState() => _PlanDaySheetState();
}

class _PlanDaySheetState extends ConsumerState<PlanDaySheet> {
  late final List<String> _picked =
      List.of(ref.read(dayJournalProvider).topFor(_today()));
  bool _saving = false;

  void _toggle(String uid) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_picked.contains(uid)) {
        _picked.remove(uid);
      } else if (_picked.length >= maxTopTasks) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            content: Text('Three is plenty. Unpick one to swap it.'),
            duration: Duration(seconds: 2),
          ));
      } else {
        _picked.add(uid);
      }
    });
  }

  Future<void> _start(List<TodayTaskContext> all) async {
    setState(() => _saving = true);
    // Picked tasks belong to today, wherever they were scheduled.
    await startDay(
      ref.read(dayJournalProvider.notifier),
      picked: _picked,
      candidates: all,
    );
    if (!mounted) return;
    bumpActivityTick(ref);
    SoundService.instance.play(Sfx.sparkle);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final grouped = ref.watch(todayTasksGroupedProvider).valueOrNull;
    final habits = ref.watch(habitsProvider).valueOrNull?.length ?? 0;

    final sections = <(String, List<TodayTaskContext>)>[
      if (grouped != null) ...[
        ('Overdue', grouped.overdue),
        ('Due today', grouped.dueToday),
        ('Inbox', grouped.inbox),
        ('This week', grouped.thisWeek),
        ('Next from your goals', grouped.upNext.take(8).toList()),
      ],
    ];
    final all = [for (final s in sections) ...s.$2];

    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                '☀️ Plan your day',
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Pick up to $maxTopTasks tasks that would make today a win. '
                '${habits > 0 ? 'Your $habits habits are on Today too.' : ''}',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            if (grouped == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (all.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Nothing waiting. Add a task with "+" on Today, or enjoy a '
                  'light day.',
                  style: tt.bodyMedium,
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final (title, items) in sections)
                      if (items.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                          child: Text(
                            title.toUpperCase(),
                            style: tt.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        for (final c in items)
                          CheckboxListTile(
                            dense: true,
                            value: _picked.contains(c.task.uid),
                            onChanged: (_) => _toggle(c.task.uid),
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(c.task.text),
                            subtitle: Text(
                              c.goal == null
                                  ? 'Inbox'
                                  : '${c.goal!.emoji} ${c.goal!.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            secondary: _picked.contains(c.task.uid)
                                ? CircleAvatar(
                                    radius: 12,
                                    backgroundColor: cs.primary,
                                    child: Text(
                                      '${_picked.indexOf(c.task.uid) + 1}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                      ],
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: FilledButton(
                onPressed: _saving ? null : () => _start(all),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(_picked.isEmpty
                    ? 'Start the day without a top 3'
                    : 'Start my day with ${_picked.length} '
                        'task${_picked.length == 1 ? '' : 's'}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Evening: wrap up the day ──────────────────────────────

const moodFaces = ['😞', '😕', '😐', '🙂', '😄'];

/// The evening close: see what got done, roll the rest to tomorrow, and
/// note how the day felt. Notes power the mood insights later.
class WrapUpSheet extends ConsumerStatefulWidget {
  const WrapUpSheet({super.key});

  @override
  ConsumerState<WrapUpSheet> createState() => _WrapUpSheetState();
}

class _WrapUpSheetState extends ConsumerState<WrapUpSheet> {
  late final _note = TextEditingController(
      text: ref.read(dayJournalProvider).noteFor(_today())?.note ?? '');
  late int _mood = ref.read(dayJournalProvider).noteFor(_today())?.mood ?? 0;
  Set<int>? _roll;
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save(List<TodayTaskContext> unfinished) async {
    if (_mood == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('How did today feel? Pick a face.')),
      );
      return;
    }
    setState(() => _saving = true);
    final roll = _roll ?? {for (final c in unfinished) c.task.id};
    await wrapUpDay(
      ref.read(dayJournalProvider.notifier),
      mood: _mood,
      note: _note.text,
      rollTaskIds: roll.toList(),
    );
    if (!mounted) return;
    bumpActivityTick(ref);
    SoundService.instance.play(Sfx.done);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(roll.isEmpty
          ? 'Day wrapped up. Rest well.'
          : 'Day wrapped up. ${roll.length} task${roll.length == 1 ? '' : 's'} '
              'moved to tomorrow.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final grouped = ref.watch(todayTasksGroupedProvider).valueOrNull;
    final habitsDone =
        ref.watch(todayHabitChecksProvider).valueOrNull?.length ?? 0;
    final pet = ref.watch(petViewProvider);
    final unfinished = [...?grouped?.overdue, ...?grouped?.dueToday];
    final roll = _roll ?? {for (final c in unfinished) c.task.id};

    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.88),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '🌙 Wrap up your day',
                  style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  habitsDone > 0
                      ? 'You ticked $habitsDone habit${habitsDone == 1 ? '' : 's'} '
                          'today. Nice.'
                      : 'Every day counts, even the quiet ones.',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Text('How did today feel?',
                    style:
                        tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 0; i < moodFaces.length; i++)
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _mood = i + 1);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _mood == i + 1
                                ? cs.primary.withValues(alpha: 0.16)
                                : Colors.transparent,
                          ),
                          child: Text(
                            moodFaces[i],
                            style:
                                TextStyle(fontSize: _mood == i + 1 ? 36 : 30),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _note,
                  maxLength: 140,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'One line about today (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (unfinished.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Move to tomorrow',
                      style:
                          tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  for (final c in unfinished)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: roll.contains(c.task.id),
                      onChanged: (v) => setState(() {
                        final next = {...roll};
                        v == true
                            ? next.add(c.task.id)
                            : next.remove(c.task.id);
                        _roll = next;
                      }),
                      title: Text(c.task.text),
                    ),
                ],
                if (pet?.urgentNeed != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${pet!.name} is ${pet.urgentNeed!.complaint}. Look after '
                    '${pet.name} in the Pet tab before bed.',
                    style: tt.bodySmall?.copyWith(color: cs.error),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : () => _save(unfinished),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Wrap up'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
