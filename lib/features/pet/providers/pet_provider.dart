import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/services/synced_settings.dart';
import '../../companion/providers/companion_provider.dart';
import '../data/pet_repository.dart';
import '../domain/pet_domain.dart';

/// Ticks once a minute so needs visibly drain while a screen is open.
final petClockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(minutes: 1), (_) => DateTime.now());
});

/// The stored pet, or null before one has been adopted.
class PetController extends AsyncNotifier<PetState?> {
  @override
  Future<PetState?> build() async {
    // A pet changed on another device lands in preferences behind our back.
    final sub =
        SyncedSettings.instance.changes.listen((_) => ref.invalidateSelf());
    ref.onDispose(sub.cancel);
    return loadInitial();
  }

  /// Where the pet is read from and written to. Tests override these.
  Future<PetState?> loadInitial() => PetRepository.instance.load();
  Future<void> persist(PetState next) => PetRepository.instance.save(next);

  Future<void> _commit(PetState next) async {
    state = AsyncData(next);
    await persist(next);
  }

  /// The pet brought up to date, so every action starts from real needs.
  PetState? get _now => state.valueOrNull?.decayed(DateTime.now());

  Future<void> adopt(PetSpecies species, {String? name}) =>
      _commit(PetState.adopt(species, name: name));

  /// Switching keeps the inventory and coins; items for the old species stay
  /// owned and work again if you switch back.
  Future<void> switchSpecies(PetSpecies species) async {
    final current = _now;
    if (current == null) return adopt(species);
    await _commit(current.copyWith(
      species: species,
      name: speciesInfo[species]!.defaultName,
    ));
  }

  Future<void> rename(String name) async {
    final current = _now;
    if (current == null || name.trim().isEmpty) return;
    await _commit(current.copyWith(name: name.trim()));
  }

  /// Throws [PetActionError] with a message for the user when it can't.
  Future<void> purchase(StoreItem item) async {
    final current = _now;
    if (current == null) return;
    final xp = (await ref.read(gameStateProvider.future)).level.xp;
    await _commit(buy(current, item, balance: current.balance(xp)));
  }

  Future<void> useItem(StoreItem item) async {
    final current = _now;
    if (current == null) return;
    await _commit(use(current, item));
  }

  Future<void> patPet() async {
    final current = _now;
    if (current == null) return;
    await _commit(pat(current));
  }
}

final petControllerProvider =
    AsyncNotifierProvider<PetController, PetState?>(PetController.new);

/// The pet as it is right now, needs drained to the current minute.
final petViewProvider = Provider<PetState?>((ref) {
  final pet = ref.watch(petControllerProvider).valueOrNull;
  final now = ref.watch(petClockProvider).valueOrNull ?? DateTime.now();
  return pet?.decayed(now);
});

/// Coins available to spend: earned from XP, plus the adoption gift, minus
/// what has been spent.
final coinBalanceProvider = Provider<int>((ref) {
  final pet = ref.watch(petControllerProvider).valueOrNull;
  final xp = ref.watch(gameStateProvider).valueOrNull?.level.xp ?? 0;
  if (pet == null) return coinsEarned(xp);
  return pet.balance(xp).clamp(0, 1 << 30);
});
