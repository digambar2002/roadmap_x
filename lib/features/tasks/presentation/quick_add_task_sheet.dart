import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/layout/adaptive_sheet.dart';
import '../../../core/models/models.dart';
import '../../analytics/providers/activity_provider.dart';
import '../../goals/data/goal_repository.dart';
import '../../milestones/data/milestone_repository.dart';
import '../data/task_repository.dart';
import '../domain/repeat_rule.dart';
import 'repeat_selector.dart';

/// Opens quick capture. [initialText] pre-fills it, e.g. text shared from
/// another app. Returns how many tasks were added.
Future<int?> showQuickAddTask(BuildContext context, {String? initialText}) =>
    showAdaptiveSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => QuickAddTaskSheet(initialText: initialText),
    );

enum _When { today, tomorrow, someday }

/// Capture a task in seconds: type, press Enter, type the next one.
///
/// No goal is needed. Tasks land in the Inbox unless a goal is picked, and
/// can be moved into one later from the task's options.
class QuickAddTaskSheet extends ConsumerStatefulWidget {
  const QuickAddTaskSheet({super.key, this.initialText});

  final String? initialText;

  @override
  ConsumerState<QuickAddTaskSheet> createState() => _QuickAddTaskSheetState();
}

class _QuickAddTaskSheetState extends ConsumerState<QuickAddTaskSheet> {
  late final _text = TextEditingController(text: widget.initialText ?? '');
  final _focus = FocusNode();
  _When _when = _When.today;
  RepeatRule? _repeat;
  bool _showRepeat = false;
  ({int id, String label})? _milestone;
  int _added = 0;
  String? _lastAdded;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  DateTime? get _dueDate {
    final now = DateTime.now();
    return switch (_when) {
      _When.today => DateTime(now.year, now.month, now.day),
      _When.tomorrow => DateTime(now.year, now.month, now.day + 1),
      _When.someday =>
        _repeat == null ? null : DateTime(now.year, now.month, now.day),
    };
  }

  /// Saves the current line and clears the field for the next one.
  Future<bool> _add() async {
    final text = _text.text.trim();
    if (text.isEmpty) return false;
    HapticFeedback.lightImpact();
    await TaskRepository.instance.create(
      milestoneId: _milestone?.id,
      text: text,
      dueDate: _dueDate,
      repeat: _repeat?.name,
    );
    if (!mounted) return true;
    bumpActivityTick(ref);
    setState(() {
      _added++;
      _lastAdded = text;
      _text.clear();
    });
    _focus.requestFocus();
    return true;
  }

  Future<void> _done() async {
    await _add();
    if (mounted) Navigator.of(context).pop(_added);
  }

  Future<void> _pickGoal() async {
    final picked = await pickMilestone(context);
    if (picked == null || !mounted) return;
    setState(() => _milestone = picked.id == -1 ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'New task',
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              focusNode: _focus,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'What needs doing?',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _add(),
            ),
            if (_lastAdded != null) ...[
              const SizedBox(height: 6),
              Text(
                '✓ Added "$_lastAdded"${_added > 1 ? ' · $_added so far' : ''}. '
                'Type the next one.',
                style: tt.labelSmall?.copyWith(color: const Color(0xFF10B981)),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final (w, label) in const [
                  (_When.today, 'Today'),
                  (_When.tomorrow, 'Tomorrow'),
                  (_When.someday, 'No date'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _when == w,
                    onSelected: (_) => setState(() => _when = w),
                  ),
                ActionChip(
                  avatar: Icon(
                    _repeat == null
                        ? Icons.repeat_rounded
                        : Icons.repeat_on_rounded,
                    size: 18,
                  ),
                  label: Text(_repeat?.label ?? 'Repeat'),
                  onPressed: () => setState(() => _showRepeat = !_showRepeat),
                ),
                ActionChip(
                  avatar: Icon(
                    _milestone == null
                        ? Icons.inbox_outlined
                        : Icons.flag_outlined,
                    size: 18,
                  ),
                  label: Text(_milestone?.label ?? 'Inbox'),
                  onPressed: _pickGoal,
                ),
              ],
            ),
            if (_showRepeat) ...[
              const SizedBox(height: 8),
              RepeatSelector(
                value: _repeat,
                onChanged: (r) => setState(() => _repeat = r),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _milestone == null
                        ? 'Lands in your Inbox. Move it into a goal any time.'
                        : 'Added to ${_milestone!.label}.',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _done, child: const Text('Done')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Lets the user choose a goal's milestone, or the Inbox (returned as id -1).
Future<({int id, String label})?> pickMilestone(BuildContext context) {
  return showAdaptiveSheet<({int id, String label})>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => const _MilestonePicker(),
  );
}

class _MilestonePicker extends StatelessWidget {
  const _MilestonePicker();

  Future<List<(Goal, List<Milestone>)>> _load() async {
    final goals = (await GoalRepository.instance.getAll())
        .where((g) => !g.isArchived)
        .toList();
    return [
      for (final g in goals)
        (g, await MilestoneRepository.instance.getForGoal(g.id)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: FutureBuilder<List<(Goal, List<Milestone>)>>(
          future: _load(),
          builder: (context, snap) {
            final data = snap.data;
            if (data == null) {
              return const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    'Where does it go?',
                    style:
                        tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.inbox_outlined),
                  title: const Text('Inbox'),
                  subtitle: const Text('No goal yet'),
                  onTap: () => Navigator.pop(context, (id: -1, label: 'Inbox')),
                ),
                for (final (goal, milestones) in data)
                  if (milestones.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                      child: Text(
                        '${goal.emoji} ${goal.name}',
                        style: tt.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    for (final m in milestones)
                      ListTile(
                        dense: true,
                        contentPadding:
                            const EdgeInsets.only(left: 36, right: 20),
                        title: Text(m.title),
                        onTap: () => Navigator.pop(
                          context,
                          (id: m.id, label: '${goal.emoji} ${m.title}'),
                        ),
                      ),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}
