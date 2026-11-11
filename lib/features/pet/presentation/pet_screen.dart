import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/gamification/progress_engine.dart';
import '../../../core/layout/adaptive_page.dart';
import '../../../core/layout/adaptive_sheet.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../shared/widgets/item_actions.dart';
import '../domain/pet_domain.dart';
import '../providers/pet_provider.dart';
import 'pet_avatar.dart';
import '../../../core/services/sound_service.dart';
import '../../../shared/widgets/text_input_dialog.dart';

Sfx soundFor(StoreItem item) => switch (item.category) {
      ItemCategory.food => Sfx.eat,
      ItemCategory.drink => Sfx.drink,
      ItemCategory.toy => Sfx.play,
      ItemCategory.care => item.id == 'soap' ? Sfx.wash : Sfx.sparkle,
    };

PetAction actionFor(StoreItem item) => switch (item.category) {
      ItemCategory.food => PetAction.eat,
      ItemCategory.drink => PetAction.drink,
      ItemCategory.toy => PetAction.play,
      ItemCategory.care => item.id == 'soap' ? PetAction.wash : PetAction.love,
    };

/// The Pet tab: your companion's room, its needs, what you own, and the
/// store. Coins come from XP, so the way to look after your pet is to get
/// things done.
class PetScreen extends ConsumerStatefulWidget {
  const PetScreen({super.key});

  @override
  ConsumerState<PetScreen> createState() => _PetScreenState();
}

class _PetScreenState extends ConsumerState<PetScreen> {
  PetAction _action = PetAction.none;
  int _nonce = 0;
  String? _actionEmoji;
  DateTime _lastPatSaved = DateTime(2000);
  static bool _whimperedThisSession = false;

  void _play(PetAction action, {String? emoji}) {
    setState(() {
      _action = action;
      _actionEmoji = emoji;
      _nonce++;
    });
  }

  Future<void> _use(StoreItem item) async {
    HapticFeedback.lightImpact();
    try {
      await ref.read(petControllerProvider.notifier).useItem(item);
      SoundService.instance.play(soundFor(item));
      _play(actionFor(item), emoji: item.emoji);
    } on PetActionError catch (e) {
      SoundService.instance.play(Sfx.nope);
      _toast(e.message);
    }
  }

  Future<void> _pat() async {
    HapticFeedback.selectionClick();
    SoundService.instance.play(Sfx.pat, volume: 0.8);
    _play(PetAction.love);
    // Petting is free and frequent; only write it occasionally.
    final now = DateTime.now();
    if (now.difference(_lastPatSaved).inSeconds >= 10) {
      _lastPatSaved = now;
      await ref.read(petControllerProvider.notifier).patPet();
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _rename(PetState pet) async {
    final result = await showTextInputDialog(
      context,
      title: 'Rename your pet',
      initialValue: pet.name,
      maxLength: 20,
    );
    if (result == null || !mounted) return;
    await ref.read(petControllerProvider.notifier).rename(result);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final stored = ref.watch(petControllerProvider);
    final pet = ref.watch(petViewProvider);

    if (pet?.urgentNeed != null && !_whimperedThisSession) {
      _whimperedThisSession = true;
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => SoundService.instance.play(Sfx.whimper));
    }

    return Scaffold(
      backgroundColor: cs.surface,
      body: AdaptivePage(
        child: SafeArea(
          child: stored.when(
            skipLoadingOnReload: true,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (_) => pet == null
                ? const AdoptView()
                : _PetRoom(
                    pet: pet,
                    action: _action,
                    nonce: _nonce,
                    actionEmoji: _actionEmoji,
                    onPat: _pat,
                    onUse: _use,
                    onRename: () => _rename(pet),
                    onStore: () => StoreSheet.show(context),
                    onChangePet: () => showAdaptiveSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const AdoptView(switching: true),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _PetRoom extends ConsumerWidget {
  const _PetRoom({
    required this.pet,
    required this.action,
    required this.nonce,
    required this.actionEmoji,
    required this.onPat,
    required this.onUse,
    required this.onRename,
    required this.onStore,
    required this.onChangePet,
  });

  final PetState pet;
  final PetAction action;
  final int nonce;
  final String? actionEmoji;
  final VoidCallback onPat;
  final ValueChanged<StoreItem> onUse;
  final VoidCallback onRename;
  final VoidCallback onStore;
  final VoidCallback onChangePet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final coins = ref.watch(coinBalanceProvider);
    final info = speciesInfo[pet.species]!;
    final urgent = pet.urgentNeed;
    final owned = [
      for (final item in storeItems)
        if ((pet.inventory[item.id] ?? 0) > 0 && item.suits(pet.species)) item,
    ];

    return ListView(
      padding:
          EdgeInsets.fromLTRB(context.pageGutter, 16, context.pageGutter, 32),
      children: [
        // ── Header ───────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pet.name,
                    style: tt.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${info.label} · ${pet.mood.label}',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            _CoinPill(coins: coins),
            ItemActionsButton(
              title: pet.name,
              size: 22,
              actions: () => [
                ItemAction(
                  label: 'Rename',
                  icon: Icons.edit_outlined,
                  onSelected: onRename,
                ),
                ItemAction(
                  label: 'Change pet',
                  icon: Icons.pets_rounded,
                  onSelected: onChangePet,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Room ─────────────────────────────────────────
        Container(
          height: 300,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                info.belly.withValues(alpha: 0.35),
                cs.primary.withValues(alpha: 0.10),
              ],
            ),
            border: Border.all(color: cs.outline),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Floor line.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 70,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.06),
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(24)),
                  ),
                ),
              ),
              Positioned(
                bottom: 18,
                child: PetAvatar(
                  species: pet.species,
                  mood: pet.mood,
                  action: action,
                  actionNonce: nonce,
                  actionEmoji: actionEmoji,
                  size: 230,
                  onTap: onPat,
                ),
              ),
              if (urgent != null)
                Positioned(
                  top: 14,
                  child: _SpeechBubble(
                    text: 'I\'m ${urgent.complaint}! ${urgent.emoji}',
                  ),
                )
              else
                Positioned(
                  top: 14,
                  child: Text(
                    'Tap ${pet.name} to say hi',
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Needs ────────────────────────────────────────
        for (final need in PetNeed.values)
          _NeedBar(need: need, value: pet.need(need)),
        const SizedBox(height: 16),

        // ── Inventory ────────────────────────────────────
        Row(
          children: [
            Text(
              'Your items',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: onStore,
              icon: const Text('🛒'),
              label: const Text('Store'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (owned.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outline),
            ),
            child: Text(
              'Nothing yet. Buy food and water in the store, then tap an item '
              'to give it to ${pet.name}.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          )
        else
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: owned.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final item = owned[i];
                return _ItemTile(
                  item: item,
                  count: pet.inventory[item.id] ?? 0,
                  onTap: () => onUse(item),
                );
              },
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'Earn coins by getting things done: every $xpPerCoin XP is 1 coin. '
          'A habit is ${XpRules.habit ~/ xpPerCoin} coins, a task '
          '${XpRules.task ~/ xpPerCoin}, a perfect day '
          '${XpRules.perfectDay ~/ xpPerCoin} more.',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _CoinPill extends StatelessWidget {
  const _CoinPill({required this.coins});
  final int coins;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '🪙 $coins',
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: Color(0xFFB45309),
        ),
      ),
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.error.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text,
        style: TextStyle(fontWeight: FontWeight.w700, color: cs.error),
      ),
    );
  }
}

Color needColor(double v) {
  if (v >= 60) return const Color(0xFF10B981);
  if (v >= lowNeed) return const Color(0xFFF59E0B);
  return const Color(0xFFEF4444);
}

class _NeedBar extends StatelessWidget {
  const _NeedBar({required this.need, required this.value});
  final PetNeed need;
  final double value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
              width: 26,
              child: Text(need.emoji, style: const TextStyle(fontSize: 18))),
          SizedBox(
            width: 52,
            child: Text(need.label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: value / 100),
                duration: const Duration(milliseconds: 500),
                builder: (_, v, __) => LinearProgressIndicator(
                  value: v,
                  minHeight: 10,
                  backgroundColor: cs.outline.withValues(alpha: 0.35),
                  valueColor: AlwaysStoppedAnimation(needColor(value)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 30,
            child: Text(
              '${value.round()}',
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile(
      {required this.item, required this.count, required this.onTap});
  final StoreItem item;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 76,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outline),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(item.emoji, style: const TextStyle(fontSize: 30)),
                    const SizedBox(height: 4),
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '×$count',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Store ─────────────────────────────────────────────────

String effectSummary(StoreItem item) => [
      for (final e in item.effects.entries) '${e.key.emoji}+${e.value.round()}',
    ].join('  ');

/// Food and supplies for the current pet, paid for with coins.
class StoreSheet extends ConsumerWidget {
  const StoreSheet({super.key});

  static Future<void> show(BuildContext context) => showAdaptiveSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const StoreSheet(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final pet = ref.watch(petViewProvider);
    final coins = ref.watch(coinBalanceProvider);
    if (pet == null) return const SizedBox.shrink();

    final items = storeItems.where((i) => i.suits(pet.species)).toList()
      ..sort((a, b) => a.category.index != b.category.index
          ? a.category.index.compareTo(b.category.index)
          : a.price.compareTo(b.price));

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Store for ${pet.name}',
                      style:
                          tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  _CoinPill(coins: coins),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final item = items[i];
                  final owned = pet.inventory[item.id] ?? 0;
                  final affordable = coins >= item.price;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cs.outline),
                    ),
                    child: Row(
                      children: [
                        Text(item.emoji, style: const TextStyle(fontSize: 30)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                owned > 0
                                    ? '${effectSummary(item)}   · own $owned'
                                    : effectSummary(item),
                                style: tt.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.tonal(
                          onPressed: affordable
                              ? () async {
                                  HapticFeedback.lightImpact();
                                  try {
                                    await ref
                                        .read(petControllerProvider.notifier)
                                        .purchase(item);
                                    SoundService.instance.play(Sfx.coin);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                        ..hideCurrentSnackBar()
                                        ..showSnackBar(SnackBar(
                                          content: Text(
                                              'Bought ${item.name} ${item.emoji}'),
                                          duration: const Duration(seconds: 1),
                                        ));
                                    }
                                  } on PetActionError catch (e) {
                                    SoundService.instance.play(Sfx.nope);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content: Text(e.message)));
                                    }
                                  }
                                }
                              : null,
                          child: Text('🪙 ${item.price}'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (coins < 3)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'Out of coins. Tick a habit or finish a task to earn more.',
                  textAlign: TextAlign.center,
                  style: tt.bodySmall?.copyWith(color: cs.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Adoption ──────────────────────────────────────────────

/// Pick one of the five pets. Also used to switch pets later.
class AdoptView extends ConsumerStatefulWidget {
  const AdoptView({super.key, this.switching = false});

  final bool switching;

  @override
  ConsumerState<AdoptView> createState() => _AdoptViewState();
}

class _AdoptViewState extends ConsumerState<AdoptView> {
  PetSpecies _selected = PetSpecies.cat;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final info = speciesInfo[_selected]!;

    return ListView(
      shrinkWrap: true,
      padding:
          EdgeInsets.fromLTRB(context.pageGutter, 16, context.pageGutter, 24),
      children: [
        Text(
          widget.switching ? 'Change pet' : 'Adopt a companion',
          style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          widget.switching
              ? 'Your coins and items stay with you.'
              : 'Get things done to earn coins, then spend them on food and '
                  'treats. You start with $adoptionGift coins.',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Center(
          child: PetAvatar(
            key: ValueKey(_selected),
            species: _selected,
            mood: PetMood.happy,
            size: 190,
            action: PetAction.love,
            actionNonce: _selected.index,
          ),
        ),
        Center(
          child: Text(
            info.blurb,
            textAlign: TextAlign.center,
            style: tt.bodyMedium,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in PetSpecies.values)
              ChoiceChip(
                label: Text(speciesInfo[s]!.label),
                selected: _selected == s,
                onSelected: (_) => setState(() => _selected = s),
              ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () async {
            final controller = ref.read(petControllerProvider.notifier);
            SoundService.instance.play(Sfx.sparkle);
            if (widget.switching) {
              await controller.switchSpecies(_selected);
              if (context.mounted) Navigator.pop(context);
            } else {
              await controller.adopt(_selected);
            }
          },
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text(
            widget.switching
                ? 'Switch to ${info.label}'
                : 'Adopt ${info.defaultName} the ${info.label}',
          ),
        ),
      ],
    );
  }
}
