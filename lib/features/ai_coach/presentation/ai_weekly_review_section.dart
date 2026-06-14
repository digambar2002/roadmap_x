import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../analytics/providers/analytics_provider.dart';
import '../providers/ai_coach_provider.dart';

class AiWeeklyReviewSection extends ConsumerStatefulWidget {
  const AiWeeklyReviewSection({super.key, required this.data});

  final AnalyticsData data;

  @override
  ConsumerState<AiWeeklyReviewSection> createState() =>
      _AiWeeklyReviewSectionState();
}

class _AiWeeklyReviewSectionState extends ConsumerState<AiWeeklyReviewSection> {
  bool _showAiReview = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final review = widget.data.weeklyReview;
    final hasAi = ref.watch(hasAiCoachProvider);
    final coachAsync = ref.watch(weeklyCoachReviewProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFA78BFA).withOpacity(0.14),
            cs.surfaceContainerHighest,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('📋', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Weekly Review',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (hasAi)
                TextButton.icon(
                  onPressed: coachAsync.isLoading
                      ? null
                      : () async {
                          if (!_showAiReview) {
                            await ref
                                .read(weeklyCoachReviewProvider.notifier)
                                .load(forceRefresh: true);
                          }
                          setState(() => _showAiReview = !_showAiReview);
                        },
                  icon: coachAsync.isLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _showAiReview
                              ? Icons.expand_less
                              : Icons.auto_awesome,
                          size: 16,
                        ),
                  label: Text(_showAiReview ? 'Hide AI' : 'AI insights'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_showAiReview && hasAi)
            coachAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text(
                e.toString(),
                style: tt.bodySmall?.copyWith(color: cs.error),
              ),
              data: (aiReview) {
                if (aiReview == null) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(aiReview.summary, style: tt.bodyMedium),
                    if (aiReview.wins.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text('Wins',
                          style: tt.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      ...aiReview.wins.map(
                        (w) => Text('✓ $w', style: tt.bodySmall),
                      ),
                    ],
                    if (aiReview.blockers.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Suggestions',
                          style: tt.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      ...aiReview.blockers.map(
                        (s) => Text('→ $s', style: tt.bodySmall),
                      ),
                    ],
                    if (aiReview.nextWeekFocus.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Next week: ${aiReview.nextWeekFocus.first}',
                          style: tt.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                  ],
                );
              },
            )
          else
            Text(review.summary, style: tt.bodyMedium),
          const SizedBox(height: 14),
          Row(
            children: [
              _ReviewStat(
                label: 'Complete',
                value: '${review.completedGoals}',
                color: const Color(0xFF34D399),
              ),
              const SizedBox(width: 10),
              _ReviewStat(
                label: 'Need focus',
                value: '${review.needsAttention}',
                color: const Color(0xFFFBBF24),
              ),
              const SizedBox(width: 10),
              _ReviewStat(
                label: 'Overdue',
                value: '${review.overdueTasks}',
                color: const Color(0xFFF87171),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReviewStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ReviewStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
