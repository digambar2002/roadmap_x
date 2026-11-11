import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:roadmap_x/core/gamification/gamification_service.dart';
import 'package:roadmap_x/core/gamification/progress_engine.dart';
import 'package:roadmap_x/features/companion/providers/companion_provider.dart';
import 'package:roadmap_x/features/pet/domain/pet_domain.dart';
import 'package:roadmap_x/features/pet/presentation/pet_screen.dart';
import 'package:roadmap_x/features/pet/providers/pet_provider.dart';

/// In-memory controller: the screen's logic, without the database.
class _MemoryPet extends PetController {
  PetState? saved;
  @override
  Future<PetState?> loadInitial() async => null;
  @override
  Future<void> persist(PetState next) async => saved = next;
}

void main() {
  // 100 XP = 20 coins, plus the 30-coin adoption gift.
  final game = GameState(
    openTasksToday: 0,
    snapshot: GameSnapshot(
      level: levelFor(100),
      today: DayActivity(
        day: DateTime(2026, 11, 11),
        habitsDue: 0,
        habitsDone: 0,
        tasksDone: 0,
      ),
      recentDays: const [],
    ),
  );

  // The pet idles in a loop, so step time instead of settling.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('adopt a pet, buy food in the store, feed it', (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final memory = _MemoryPet();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        petControllerProvider.overrideWith(() => memory),
        gameStateProvider.overrideWith((ref) async => game),
        petClockProvider.overrideWith((ref) => Stream.value(DateTime.now())),
      ],
      child: const MaterialApp(home: PetScreen()),
    ));
    await settle(tester);

    // ── Adopt ──────────────────────────────────────────
    expect(find.text('Adopt a companion'), findsOneWidget);
    for (final s in PetSpecies.values) {
      expect(find.text(speciesInfo[s]!.label), findsOneWidget);
    }
    await tester.tap(find.text('Bunny'));
    await settle(tester);
    await tester.tap(find.text('Adopt Clover the Bunny'));
    await settle(tester);
    expect(find.text('Clover'), findsOneWidget);
    expect(find.text('🪙 50'), findsOneWidget);
    expect(memory.saved?.species, PetSpecies.bunny);

    // ── Buy ────────────────────────────────────────────
    await tester.tap(find.text('Store'));
    await settle(tester);
    expect(find.text('Store for Clover'), findsOneWidget);
    expect(find.text('Fish'), findsNothing, reason: 'cat food is not offered');
    final carrot = itemById('carrot')!;
    await tester.tap(find.text('🪙 ${carrot.price}').first);
    await settle(tester);
    expect(memory.saved!.inventory['carrot'], 1);
    expect(find.text('🪙 ${50 - carrot.price}'), findsWidgets);

    // Close the store.
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);

    // ── Feed ───────────────────────────────────────────
    final before = memory.saved!.need(PetNeed.food);
    await tester.tap(find.text('Carrot'));
    await settle(tester);
    expect(memory.saved!.inventory.containsKey('carrot'), isFalse);
    expect(memory.saved!.need(PetNeed.food), greaterThan(before));
  });
}
