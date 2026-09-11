import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/layout/adaptive_page.dart';
import '../../../core/layout/adaptive_sheet.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/models/habit_icons.dart';
import '../../../core/models/models.dart';
import '../../../shared/widgets/bottom_sheet_handle.dart';
import '../../../shared/widgets/confirmation_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../data/habit_repository.dart';
import '../providers/habit_provider.dart';

/// Manages the daily non-negotiables.
///
/// Everything saves as it is edited — renaming commits when the field loses
/// focus, the icon the moment one is picked, order on drop. There is no save
/// button because there is nothing a save button would do that has not already
/// happened.
class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final habitsAsync = ref.watch(habitsProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          'Non-negotiables',
          style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        backgroundColor: cs.surface,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Add habit',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _add(context, ref),
          ),
        ],
      ),
      body: AdaptivePage(
        child: habitsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('Error: $error')),
          data: (habits) {
            if (habits.isEmpty) {
              return Center(
                child: Padding(
                  padding: EdgeInsets.all(context.pageGutter),
                  child: EmptyState(
                    emoji: '🎯',
                    title: 'No habits yet',
                    subtitle:
                        'Add the few things you want to do every day. They '
                        'show up on your dashboard and drive your streak.',
                    buttonLabel: 'Add your first habit',
                    onButton: () => _add(context, ref),
                  ),
                ),
              );
            }

            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    context.pageGutter,
                    8,
                    context.pageGutter,
                    4,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'A day counts towards your streak once every habit '
                          'here is ticked.',
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      context.pageGutter,
                      4,
                      context.pageGutter,
                      96,
                    ),
                    itemCount: habits.length,
                    proxyDecorator: (child, _, __) =>
                        Material(color: Colors.transparent, child: child),
                    onReorder: (oldIndex, newIndex) async {
                      if (newIndex > oldIndex) newIndex--;
                      final reordered = List<Habit>.from(habits);
                      reordered.insert(
                        newIndex,
                        reordered.removeAt(oldIndex),
                      );
                      await HabitRepository.instance.reorder(reordered);
                    },
                    itemBuilder: (context, i) => _HabitRow(
                      key: ValueKey(habits[i].uid),
                      habit: habits[i],
                      index: i,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: habitsAsync.valueOrNull?.isEmpty ?? true
          ? null
          : FloatingActionButton.extended(
              heroTag: 'habits_fab',
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add habit'),
            ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final iconKey = await pickHabitIcon(context, selected: HabitIcons.fallbackKey);
    if (iconKey == null || !context.mounted) return;
    await HabitRepository.instance.create(label: '', iconKey: iconKey);
  }
}

class _HabitRow extends ConsumerStatefulWidget {
  const _HabitRow({super.key, required this.habit, required this.index});

  final Habit habit;
  final int index;

  @override
  ConsumerState<_HabitRow> createState() => _HabitRowState();
}

class _HabitRowState extends ConsumerState<_HabitRow> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.habit.label);
  late final FocusNode _focus = FocusNode()..addListener(_commitOnBlur);

  @override
  void didUpdateWidget(covariant _HabitRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Accept a label changed elsewhere (another device, a restore), but never
    // while the user is part way through typing it.
    if (widget.habit.label != oldWidget.habit.label &&
        !_focus.hasFocus &&
        _ctrl.text != widget.habit.label) {
      _ctrl.text = widget.habit.label;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_commitOnBlur);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _commitOnBlur() {
    if (_focus.hasFocus) return;
    _commit();
  }

  Future<void> _commit() async {
    final text = _ctrl.text.trim();
    if (text == widget.habit.label) return;
    widget.habit.label = text;
    await HabitRepository.instance.update(widget.habit);
  }

  Future<void> _changeIcon() async {
    final key = await pickHabitIcon(context, selected: widget.habit.iconKey);
    if (key == null || key == widget.habit.iconKey) return;
    widget.habit.iconKey = key;
    await HabitRepository.instance.update(widget.habit);
  }

  Future<void> _delete() async {
    final label =
        widget.habit.label.isEmpty ? 'this habit' : '"${widget.habit.label}"';
    final confirmed = await ConfirmationDialog.show(
      context,
      title: 'Remove habit?',
      message: 'Remove $label from your daily list? Past check-ins are kept, '
          'so your history stays accurate.',
      confirmLabel: 'Remove',
    );
    if (!confirmed) return;
    await HabitRepository.instance.delete(widget.habit.id);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outline),
          color: cs.surfaceContainerHighest,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Change icon',
              onPressed: _changeIcon,
              icon: Icon(
                HabitIcons.resolve(widget.habit.iconKey),
                color: cs.primary,
              ),
            ),
            Expanded(
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Name this habit',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                ),
                onSubmitted: (_) => _commit(),
              ),
            ),
            IconButton(
              tooltip: 'Remove',
              onPressed: _delete,
              icon: Icon(Icons.delete_outline_rounded, color: cs.error),
            ),
            ReorderableDragStartListener(
              index: widget.index,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.drag_handle_rounded,
                    color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grid of the available habit icons. Returns null if dismissed.
Future<String?> pickHabitIcon(
  BuildContext context, {
  required String selected,
}) {
  return showAdaptiveSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (sheetContext) {
      final cs = Theme.of(sheetContext).colorScheme;
      final tt = Theme.of(sheetContext).textTheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BottomSheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'Pick an icon',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Flexible(
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: 6,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  for (final key in HabitIcons.keys)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(sheetContext, key),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: key == selected ? cs.primary : cs.outline,
                            width: key == selected ? 2 : 1,
                          ),
                          color: key == selected
                              ? cs.primary.withValues(alpha: 0.12)
                              : Colors.transparent,
                        ),
                        child: Icon(
                          HabitIcons.catalog[key],
                          color:
                              key == selected ? cs.primary : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
