import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/gamification/gamification_service.dart';
import '../../../core/gamification/progress_engine.dart';
import '../../../core/layout/adaptive_sheet.dart';
import '../../../core/services/habit_checkin_service.dart';
import '../../../core/services/shared_preferences_provider.dart';
import '../providers/companion_provider.dart';

/// The companion's face for its kind, growth stage and mood.
String companionEmoji(CompanionKind kind, int stage, CompanionMood mood) {
  if (kind == CompanionKind.plant) {
    if (mood == CompanionMood.sick) return '🥀';
    return const ['🌱', '🪴', '🌿', '🌳'][stage.clamp(0, 3)];
  }
  return switch (mood) {
    CompanionMood.happy => '😸',
    CompanionMood.content => '😺',
    CompanionMood.bored => '😼',
    CompanionMood.tired => '😿',
    CompanionMood.sick => '🙀',
  };
}

Color healthColor(int health) {
  if (health >= 60) return const Color(0xFF10B981);
  if (health >= 30) return const Color(0xFFF59E0B);
  return const Color(0xFFEF4444);
}

/// The top of the Today tab: the perfect-day ring around the companion,
/// its health, and what today has earned it.
class CompanionCard extends ConsumerStatefulWidget {
  const CompanionCard({super.key, this.streak = 0});

  final int streak;

  @override
  ConsumerState<CompanionCard> createState() => _CompanionCardState();
}

class _CompanionCardState extends ConsumerState<CompanionCard> {
  static const _celebratedKey = 'perfect_day_celebrated';
  static const _levelSeenKey = 'level_seen';

  final _confetti = ConfettiController(duration: const Duration(seconds: 2));

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  /// Celebrates a perfect day and a level-up once each, never on every
  /// rebuild or relaunch.
  void _maybeCelebrate(GameState state) {
    final prefs = ref.read(sharedPreferencesProvider);
    final todayKey = HabitCheckinService.dayKeyFor(DateTime.now());
    final messenger = ScaffoldMessenger.maybeOf(context);

    if (state.isPerfectToday && prefs.getString(_celebratedKey) != todayKey) {
      prefs.setString(_celebratedKey, todayKey);
      HapticFeedback.heavyImpact();
      _confetti.play();
      messenger?.showSnackBar(SnackBar(
        content: Text(
          'Perfect day! +${XpRules.perfectDay} XP. '
          '${state.snapshot.name} is thriving.',
        ),
      ));
    }

    final seen = prefs.getInt(_levelSeenKey);
    final level = state.level.level;
    if (seen == null) {
      // First run: record the starting level without a fanfare.
      prefs.setInt(_levelSeenKey, level);
    } else if (level > seen) {
      prefs.setInt(_levelSeenKey, level);
      _confetti.play();
      messenger?.showSnackBar(SnackBar(
        content: Text('Level up! You are now Level $level · '
            '${state.level.title}.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<GameState>>(gameStateProvider, (_, next) {
      final value = next.valueOrNull;
      if (value != null) _maybeCelebrate(value);
    });

    final async = ref.watch(gameStateProvider);
    return async.when(
      skipLoadingOnReload: true,
      loading: () => const SizedBox(height: 132),
      error: (_, __) => const SizedBox.shrink(),
      data: (state) => Stack(
        alignment: Alignment.topCenter,
        children: [
          _CardBody(state: state, streak: widget.streak),
          ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            numberOfParticles: 24,
            shouldLoop: false,
          ),
        ],
      ),
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({required this.state, required this.streak});

  final GameState state;
  final int streak;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final snap = state.snapshot;
    final mood = state.mood;
    final perfect = state.isPerfectToday;
    final ringColor = perfect ? const Color(0xFF10B981) : cs.primary;

    final String status;
    final Color statusColor;
    if (perfect) {
      status = 'Perfect day! ${snap.name} is thriving.';
      statusColor = const Color(0xFF10B981);
    } else if (state.isHungry) {
      status = state.totalToday == 0
          ? '${snap.name} is bored. Plan something for today.'
          : '${snap.name} is hungry. Finish a habit or task today.';
      statusColor = cs.error;
    } else {
      status = '${state.doneToday} of ${state.totalToday} done today';
      statusColor = cs.onSurfaceVariant;
    }

    return Material(
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: perfect
              ? const Color(0xFF10B981).withValues(alpha: 0.5)
              : cs.outline,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => CompanionSheet.show(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // ── Ring + companion ─────────────────────────
              SizedBox(
                width: 96,
                height: 96,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: state.ringProgress),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOutCubic,
                        builder: (_, value, __) => CircularProgressIndicator(
                          value: value,
                          strokeWidth: 7,
                          strokeCap: StrokeCap.round,
                          backgroundColor: cs.outline.withValues(alpha: 0.4),
                          valueColor: AlwaysStoppedAnimation(ringColor),
                        ),
                      ),
                    ),
                    _CompanionFace(
                      emoji: companionEmoji(snap.kind, snap.level.stage, mood),
                      mood: mood,
                      size: 34.0 + snap.level.stage * 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // ── Details ──────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: snap.name,
                          style: tt.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: '  ${mood.label}',
                          style: tt.labelMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    _HealthBar(health: state.health),
                    const SizedBox(height: 8),
                    Text(
                      status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(
                        color: statusColor,
                        fontWeight:
                            state.isHungry || perfect ? FontWeight.w600 : null,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        if (state.water > 0) _Chip('💧 ${state.water}'),
                        if (state.food > 0) _Chip('🍎 ${state.food}'),
                        if (state.treats > 0) const _Chip('⭐ 1'),
                        _Chip('Lv ${snap.level.level}'),
                        if (streak > 0) _Chip('🔥 $streak'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompanionFace extends StatelessWidget {
  const _CompanionFace({
    required this.emoji,
    required this.mood,
    required this.size,
  });

  final String emoji;
  final CompanionMood mood;
  final double size;

  @override
  Widget build(BuildContext context) {
    final face = Text(emoji, style: TextStyle(fontSize: size));
    // Happy companions bob; tired and unwell ones sag. Keyed by mood so the
    // animation restarts when the mood changes, not on every rebuild.
    return switch (mood) {
      CompanionMood.happy || CompanionMood.content => face
          .animate(key: ValueKey(mood), onPlay: (c) => c.repeat(reverse: true))
          .moveY(begin: 0, end: -4, duration: 900.ms, curve: Curves.easeInOut),
      CompanionMood.bored => face,
      CompanionMood.tired || CompanionMood.sick => Opacity(
          opacity: 0.75,
          child: Transform.rotate(angle: -0.12, child: face),
        ),
    };
  }
}

class _HealthBar extends StatelessWidget {
  const _HealthBar({required this.health});
  final int health;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: health / 100),
              duration: const Duration(milliseconds: 600),
              builder: (_, v, __) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor: cs.outline.withValues(alpha: 0.4),
                valueColor: AlwaysStoppedAnimation(healthColor(health)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '❤️ $health',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: cs.onSurfaceVariant,
      ),
    );
  }
}

// ── Detail sheet ──────────────────────────────────────────

/// Everything about the companion: rename it, switch plant/pet, the last
/// week of care, and how the rules work.
class CompanionSheet extends ConsumerWidget {
  const CompanionSheet({super.key});

  static Future<void> show(BuildContext context) => showAdaptiveSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const CompanionSheet(),
      );

  Future<void> _rename(
      BuildContext context, WidgetRef ref, String current) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Name your companion'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.pop(dialogContext, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.trim().isEmpty) return;
    await GamificationService.instance.setCompanion(name: result);
    ref.read(companionVersionProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final state = ref.watch(gameStateProvider).valueOrNull;
    if (state == null) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final snap = state.snapshot;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: _CompanionFace(
                emoji: companionEmoji(snap.kind, snap.level.stage, state.mood),
                mood: state.mood,
                size: 72,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  snap.name,
                  style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                IconButton(
                  tooltip: 'Rename',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => _rename(context, ref, snap.name),
                ),
              ],
            ),
            Text(
              '${state.mood.label} · Level ${snap.level.level} '
              '${snap.level.title}',
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            _HealthBar(health: state.health),
            const SizedBox(height: 16),
            Center(
              child: SegmentedButton<CompanionKind>(
                segments: const [
                  ButtonSegment(
                    value: CompanionKind.plant,
                    label: Text('Plant'),
                    icon: Text('🌱'),
                  ),
                  ButtonSegment(
                    value: CompanionKind.pet,
                    label: Text('Pet'),
                    icon: Text('🐱'),
                  ),
                ],
                selected: {snap.kind},
                onSelectionChanged: (s) async {
                  await GamificationService.instance
                      .setCompanion(kind: s.first);
                  ref.read(companionVersionProvider.notifier).state++;
                },
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'LAST 7 DAYS',
              style: tt.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final d in snap.recentDays) _CareDot(day: d),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'HOW IT WORKS',
              style: tt.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (final line in [
              '💧 Every habit you tick waters ${snap.name}.',
              '🍎 Every task you finish feeds ${snap.name}.',
              '⭐ A perfect day (all habits and today\'s tasks) is a treat '
                  'and +${XpRules.perfectDay} XP.',
              '❤️ Active days restore health. A day with nothing done costs '
                  '${-HealthRules.emptyDay} health.',
              '🌳 ${snap.name} grows as you level up, and never dies — one '
                  'good day brings it back.',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(line, style: tt.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}

class _CareDot extends StatelessWidget {
  const _CareDot({required this.day});
  final DayActivity day;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color color;
    if (day.isPerfect) {
      color = const Color(0xFF10B981);
    } else if (day.anyDone) {
      color = const Color(0xFF10B981).withValues(alpha: 0.45);
    } else {
      color = cs.error.withValues(alpha: 0.55);
    }
    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: day.isPerfect
              ? const Icon(Icons.star_rounded, size: 16, color: Colors.white)
              : null,
        ),
        const SizedBox(height: 4),
        Text(
          DateFormat('E').format(day.day).substring(0, 1),
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}
