import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../../core/models/models.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../shared/widgets/bottom_sheet_handle.dart';
import '../../../../shared/widgets/custom_button.dart';
import '../../../tasks/data/task_repository.dart';

class CreateEditTaskSheet extends HookConsumerWidget {
  final int milestoneId;
  final Color goalColor;
  final Task? task;

  const CreateEditTaskSheet({
    super.key,
    required this.milestoneId,
    required this.goalColor,
    this.task,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isEdit = task != null;

    final textCtrl = useTextEditingController(text: task?.text ?? '');
    final noteCtrl = useTextEditingController(text: task?.note ?? '');
    final priority = useState(task?.priority ?? 0);
    final dueDate = useState<DateTime?>(task?.dueDate);
    final isSaving = useState(false);
    final formKey = useMemoized(GlobalKey<FormState>.new);

    Future<void> save({bool markDone = false}) async {
      if (!formKey.currentState!.validate()) return;
      isSaving.value = true;
      try {
        if (isEdit) {
          task!
            ..text = textCtrl.text.trim()
            ..priority = priority.value
            ..dueDate = dueDate.value
            ..note = noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim();
          if (markDone && !task!.isCompleted) {
            task!.isCompleted = true;
            task!.completedAt = DateTime.now();
          }
          await TaskRepository.instance.update(task!);
        } else {
          await TaskRepository.instance.create(
            milestoneId: milestoneId,
            text: textCtrl.text.trim(),
            priority: priority.value,
            dueDate: dueDate.value,
            note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
          );
        }
        if (context.mounted) Navigator.of(context).pop();
      } finally {
        isSaving.value = false;
      }
    }

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BottomSheetHandle(),
                Text(
                  isEdit ? 'Edit Task' : 'New Task',
                  style:
                      tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),

                // Task text
                TextFormField(
                  controller: textCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Task *',
                    hintText: 'What needs to be done?',
                  ),
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Task text required'
                      : null,
                ),
                const SizedBox(height: 16),

                // Priority
                Text('Priority',
                    style:
                        tt.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _PrioritySelector(
                  value: priority.value,
                  onChanged: (v) => priority.value = v,
                ),
                const SizedBox(height: 16),

                // Due date
                _OptionalDateRow(
                  date: dueDate.value,
                  onPicked: (d) => dueDate.value = d,
                  onClear: () => dueDate.value = null,
                ),
                const SizedBox(height: 16),

                // Note
                TextFormField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    hintText: 'Any extra detail…',
                  ),
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 28),

                Row(
                  children: [
                    Expanded(
                      child: CustomButton(
                        label: isEdit ? 'Save Changes' : 'Add Task',
                        isLoading: isSaving.value,
                        onPressed: save,
                        color: goalColor,
                      ),
                    ),
                    if (isEdit && !task!.isCompleted) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: CustomButton(
                          label: 'Mark Done',
                          outlined: true,
                          color: goalColor,
                          onPressed: () => save(markDone: true),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrioritySelector extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _PrioritySelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const labels = ['Normal', 'High', 'Critical'];
    const colors = [
      Color(0xFF5A6A92),
      Color(0xFFFBBF24),
      Color(0xFFF87171),
    ];

    return Row(
      children: List.generate(3, (i) {
        final selected = value == i;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? colors[i].withOpacity(0.2)
                      : Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? colors[i]
                        : Theme.of(context).colorScheme.outline,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: colors[i],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected
                            ? colors[i]
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _OptionalDateRow extends StatelessWidget {
  final DateTime? date;
  final ValueChanged<DateTime> onPicked;
  final VoidCallback onClear;

  const _OptionalDateRow({
    required this.date,
    required this.onPicked,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 3650)),
        );
        if (picked != null) onPicked(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outline),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                date != null
                    ? AppDateUtils.formatDate(date!)
                    : 'Due date (optional)',
                style: date != null
                    ? tt.bodyMedium
                    : tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            if (date != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}
