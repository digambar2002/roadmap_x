import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/ai/ai_coach_service.dart';
import '../providers/ai_coach_provider.dart';

class DailyBriefingCard extends ConsumerWidget {
  const DailyBriefingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final briefingAsync = ref.watch(dailyBriefingProvider);
    final hasAi = ref.watch(hasAiCoachProvider);

    if (!hasAi) {
      return _SetupPrompt(cs: cs, tt: tt);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF5B9CF6).withOpacity(0.18),
            const Color(0xFFA78BFA).withOpacity(0.12),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline),
      ),
      child: briefingAsync.when(
        loading: () => const SizedBox(
          height: 96,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (error, _) => _BriefingError(
          message: error is AiCoachException ? error.message : error.toString(),
          onRetry: () => ref.read(dailyBriefingProvider.notifier).refresh(),
        ),
        data: (briefing) {
          if (briefing == null) {
            return Text(
              'Your daily briefing will appear here.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            );
          }
          return _BriefingContent(briefing: briefing, tt: tt);
        },
      ),
    ).animate().fadeIn(duration: 280.ms).slideY(begin: 0.04);
  }
}

class _BriefingContent extends ConsumerWidget {
  const _BriefingContent({required this.briefing, required this.tt});

  final DailyBriefing briefing;
  final TextTheme tt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('🤖', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Daily Briefing',
                style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Refresh briefing',
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  ref.read(dailyBriefingProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          briefing.headline,
          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        _BriefingRow(icon: '🎯', label: 'Focus', value: briefing.focusTask),
        _BriefingRow(icon: '⚡', label: 'Quick win', value: briefing.quickWin),
        _BriefingRow(icon: '⚠️', label: 'Risk', value: briefing.risk),
        const SizedBox(height: 6),
        Text('💡 ${briefing.coachTip}', style: tt.bodySmall),
      ],
    );
  }
}

class _BriefingRow extends StatelessWidget {
  const _BriefingRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final String icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: tt.bodySmall,
          children: [
            TextSpan(text: '$icon $label: '),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupPrompt extends StatelessWidget {
  const _SetupPrompt({required this.cs, required this.tt});

  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline),
      ),
      child: Row(
        children: [
          const Text('🤖', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Add your Gemini API key in Settings to unlock AI Coach — daily briefing, weekly review, chat & plan adjustments.',
              style: tt.bodySmall,
            ),
          ),
          TextButton(
            onPressed: () => context.go('/settings'),
            child: const Text('Setup'),
          ),
        ],
      ),
    );
  }
}

class _BriefingError extends StatelessWidget {
  const _BriefingError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.error_outline, color: cs.error, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: cs.error, fontSize: 13),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}
