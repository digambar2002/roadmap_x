import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/gamification/progress_engine.dart';
import '../../../core/services/habit_checkin_service.dart';
import '../../../core/services/shared_preferences_provider.dart';
import '../../pet/domain/pet_domain.dart';
import '../../pet/presentation/pet_avatar.dart';
import '../../pet/providers/pet_provider.dart';
import '../providers/companion_provider.dart';
import '../../../core/services/sound_service.dart';

/// The top of the Today tab: your pet inside the perfect-day ring, how it is
/// doing, and the coins today has earned. Tapping opens the Pet tab, where
/// coins are spent on food and supplies.
class CompanionCard extends ConsumerStatefulWidget {
  const CompanionCard({super.key, this.streak = 0, this.animate = true});

  final int streak;

  /// Off in tests, where the pet's idle loop would never let a frame settle.
  final bool animate;

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
      SoundService.instance.play(Sfx.fanfare);
      _confetti.play();
      messenger?.showSnackBar(SnackBar(
        content: Text(
          'Perfect day! +${XpRules.perfectDay} XP '
          '(+${XpRules.perfectDay ~/ xpPerCoin} coins).',
        ),
      ));
    }

    final seen = prefs.getInt(_levelSeenKey);
    final level = state.level.level;
    if (seen == null) {
      prefs.setInt(_levelSeenKey, level);
    } else if (level > seen) {
      prefs.setInt(_levelSeenKey, level);
      SoundService.instance.play(Sfx.fanfare);
      _confetti.play();
      messenger?.showSnackBar(SnackBar(
        content:
            Text('Level up! You are now Level $level · ${state.level.title}.'),
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
    final pet = ref.watch(petViewProvider);
    final coins = ref.watch(coinBalanceProvider);

    return async.when(
      skipLoadingOnReload: true,
      loading: () => const SizedBox(height: 132),
      error: (_, __) => const SizedBox.shrink(),
      data: (state) => Stack(
        alignment: Alignment.topCenter,
        children: [
          _CardBody(
            state: state,
            pet: pet,
            coins: coins,
            streak: widget.streak,
            animate: widget.animate,
          ),
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
  const _CardBody({
    required this.state,
    required this.pet,
    required this.coins,
    required this.streak,
    required this.animate,
  });

  final GameState state;
  final PetState? pet;
  final int coins;
  final int streak;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final perfect = state.isPerfectToday;
    final ringColor = perfect ? const Color(0xFF10B981) : cs.primary;
    final pet = this.pet;
    final urgent = pet?.urgentNeed;

    final String title;
    final String status;
    final Color statusColor;
    if (pet == null) {
      title = 'Adopt a pet';
      status = 'Get things done to earn coins and look after a companion.';
      statusColor = cs.onSurfaceVariant;
    } else if (urgent != null) {
      title = pet.name;
      status = coins >= 3
          ? '${pet.name} is ${urgent.complaint}. Open the Pet tab.'
          : '${pet.name} is ${urgent.complaint}. Finish a task to earn coins.';
      statusColor = cs.error;
    } else if (perfect) {
      title = pet.name;
      status = 'Perfect day! Treat ${pet.name} in the store.';
      statusColor = const Color(0xFF10B981);
    } else {
      title = pet.name;
      status = state.totalToday == 0
          ? 'Nothing planned today. Add a habit or pick tasks.'
          : '${state.doneToday} of ${state.totalToday} done today';
      statusColor = cs.onSurfaceVariant;
    }

    final coinsToday = state.xpToday ~/ xpPerCoin;

    return Material(
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: urgent != null
              ? cs.error.withValues(alpha: 0.45)
              : perfect
                  ? const Color(0xFF10B981).withValues(alpha: 0.5)
                  : cs.outline,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/pet'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // ── Ring + pet ───────────────────────────────
              SizedBox(
                width: 100,
                height: 100,
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
                    if (pet != null)
                      PetAvatar(
                        species: pet.species,
                        mood: pet.mood,
                        size: 78,
                        animate: animate,
                      )
                    else
                      Icon(Icons.pets_rounded, size: 36, color: cs.primary),
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
                          text: title,
                          style: tt.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (pet != null)
                          TextSpan(
                            text: '  ${pet.mood.label}',
                            style: tt.labelMedium
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (pet != null) ...[
                      const SizedBox(height: 8),
                      _MiniNeeds(pet: pet),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(
                        color: statusColor,
                        fontWeight:
                            urgent != null || perfect ? FontWeight.w600 : null,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        _Chip('🪙 $coins'),
                        if (coinsToday > 0) _Chip('+$coinsToday today'),
                        _Chip('Lv ${state.level.level}'),
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

/// Four tiny need bars, so the card shows what the pet is missing at a
/// glance.
class _MiniNeeds extends StatelessWidget {
  const _MiniNeeds({required this.pet});
  final PetState pet;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (final need in PetNeed.values) ...[
          Text(need.emoji, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 3),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: pet.need(need) / 100,
                minHeight: 5,
                backgroundColor: cs.outline.withValues(alpha: 0.35),
                valueColor: AlwaysStoppedAnimation(_needColor(pet.need(need))),
              ),
            ),
          ),
          if (need != PetNeed.values.last) const SizedBox(width: 6),
        ],
      ],
    );
  }

  static Color _needColor(double v) {
    if (v >= 60) return const Color(0xFF10B981);
    if (v >= lowNeed) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
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
