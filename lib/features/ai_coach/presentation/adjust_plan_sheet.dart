import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../providers/ai_coach_provider.dart';
import 'coach_sheet_host.dart';

Future<void> showAdjustPlanSheet(BuildContext context, int goalId) {
  return showCoachBottomSheet<void>(
    context,
    AdjustPlanSheet(goalId: goalId),
  );
}

class AdjustPlanSheet extends ConsumerStatefulWidget {
  const AdjustPlanSheet({super.key, required this.goalId});

  final int goalId;

  @override
  ConsumerState<AdjustPlanSheet> createState() => _AdjustPlanSheetState();
}

class _AdjustPlanSheetState extends ConsumerState<AdjustPlanSheet> {
  final _instructionController = TextEditingController();

  @override
  void dispose() {
    _instructionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adjustPlanProvider(widget.goalId));
    final notifier = ref.read(adjustPlanProvider(widget.goalId).notifier);
    final cs = Theme.of(context).colorScheme;
    final hasAi = ref.watch(hasAiCoachProvider);

    if (!hasAi) {
      return _NoAiPrompt(onClose: () => Navigator.of(context).pop());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              const Text('✨', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Adjust Plan with AI',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _instructionController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText:
                  'Optional: e.g. I can only do 30 mins/day for the next 2 weeks',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: state.isLoading
                  ? null
                  : () => notifier.generate(
                        userInstruction: _instructionController.text,
                      ),
              icon: const Icon(Icons.auto_awesome),
              label: Text(state.isLoading ? 'Generating…' : 'Generate suggestions'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: state.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  e.toString(),
                  style: TextStyle(color: cs.error),
                  textAlign: TextAlign.center,
                ),
              ),
              data: (plan) {
                if (plan == null) {
                  return Center(
                    child: Text(
                      'Generate tailored adjustments for milestones and tasks.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.rationale,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      _Section(title: 'Task changes', items: plan.taskChanges),
                      const SizedBox(height: 10),
                      _Section(
                        title: 'Milestone changes',
                        items: plan.milestoneChanges,
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('Pace: ${plan.paceAdvice}'),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        ...items.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('• $e'),
            )),
      ],
    );
  }
}

class _NoAiPrompt extends StatelessWidget {
  const _NoAiPrompt({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Adjust Plan with AI',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          const Text(
            'Add your Gemini API key in Settings to use AI Coach.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onClose, child: const Text('Close')),
        ],
      ),
    );
  }
}
