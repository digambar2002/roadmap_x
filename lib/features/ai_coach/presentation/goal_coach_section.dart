import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../providers/ai_coach_provider.dart';
import 'adjust_plan_sheet.dart';
import 'coach_chat_sheet.dart';

class GoalCoachSection extends ConsumerWidget {
  const GoalCoachSection({super.key, required this.goalId});

  final int goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasAi = ref.watch(hasAiCoachProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFA78BFA).withOpacity(0.14),
            cs.surfaceContainerHighest,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🤖', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                'AI Coach',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hasAi
                ? 'Get guidance, adjust your plan, or chat about this goal.'
                : 'Add your Gemini API key in Settings to unlock coach chat and plan adjustments.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (!hasAi)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () => context.go('/settings'),
                icon: const Icon(Icons.key_outlined, size: 18),
                label: const Text('Add API key'),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => showCoachChatSheet(context, goalId),
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('Coach Chat'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => showAdjustPlanSheet(context, goalId),
                    icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
                    label: const Text('Adjust Plan'),
                  ),
                ),
              ],
            ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }
}
