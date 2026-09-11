import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../core/services/shared_preferences_provider.dart';
import '../../../ai_coach/presentation/daily_briefing_card.dart';
import '../../../premium/presentation/premium_gate.dart';

/// The AI daily briefing, collapsed to a single row until asked for.
///
/// Two reasons it is not simply rendered inline any more. It used to occupy
/// most of the first screen before any of the user's own data appeared; and
/// because the card is only built once expanded, the briefing request is not
/// even issued for people who never open it.
class CollapsibleBriefing extends ConsumerStatefulWidget {
  const CollapsibleBriefing({super.key});

  @override
  ConsumerState<CollapsibleBriefing> createState() =>
      _CollapsibleBriefingState();
}

class _CollapsibleBriefingState extends ConsumerState<CollapsibleBriefing> {
  static const _prefsKey = 'dashboard_briefing_expanded';

  late bool _expanded =
      ref.read(sharedPreferencesProvider).getBool(_prefsKey) ?? false;

  Future<void> _toggle() async {
    setState(() => _expanded = !_expanded);
    // Remembered, so someone who does read it daily is not re-opening it every
    // morning — but the default stays closed.
    await ref.read(sharedPreferencesProvider).setBool(_prefsKey, _expanded);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _toggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outline),
              color: cs.surfaceContainerHighest,
            ),
            child: Row(
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFF5B9CF6), Color(0xFFA78BFA)],
                  ).createShader(bounds),
                  child: const Icon(Icons.auto_awesome,
                      size: 18, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Daily briefing',
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 10),
          const PremiumLock(
            title: 'Daily briefing',
            message: "Your AI coach's read on today — part of Premium.",
            child: DailyBriefingCard(),
          ),
        ],
      ],
    );
  }
}
