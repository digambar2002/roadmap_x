import 'package:flutter_test/flutter_test.dart';
import 'package:roadmap_x/features/pet/domain/pet_domain.dart';

void main() {
  final t0 = DateTime(2026, 11, 11, 8);
  PetState fresh([PetSpecies s = PetSpecies.cat]) => PetState.adopt(s, now: t0);

  test('five pets, each with something to eat in the store', () {
    expect(PetSpecies.values, hasLength(5));
    for (final s in PetSpecies.values) {
      final food = storeItems
          .where((i) => i.suits(s) && i.category == ItemCategory.food);
      expect(food, isNotEmpty, reason: '${s.name} needs food');
      expect(storeItems.any((i) => i.suits(s) && i.id == 'water'), isTrue);
    }
  });

  test('items are species-specific where it makes sense', () {
    expect(itemById('fish')!.suits(PetSpecies.cat), isTrue);
    expect(itemById('fish')!.suits(PetSpecies.dog), isFalse);
    expect(itemById('bamboo')!.suits(PetSpecies.panda), isTrue);
    expect(itemById('carrot')!.suits(PetSpecies.bunny), isTrue);
  });

  test('coins come from XP, plus the adoption gift, minus spending', () {
    expect(coinsEarned(99), 19);
    final pet = fresh();
    expect(pet.balance(100), 20 + adoptionGift);
  });

  test('needs drain over real time and never go below zero', () {
    final pet = fresh().decayed(t0.add(const Duration(hours: 10)));
    expect(pet.need(PetNeed.food), closeTo(80 - 30, 0.01));
    expect(pet.need(PetNeed.water), closeTo(80 - 35, 0.01));
    final starved = fresh().decayed(t0.add(const Duration(days: 5)));
    for (final n in PetNeed.values) {
      expect(starved.need(n), 0);
    }
    expect(starved.mood, PetMood.unwell);
    expect(starved.urgentNeed, isNotNull);
  });

  test('buying spends coins and adds to the inventory', () {
    final fish = itemById('fish')!;
    final pet = buy(fresh(), fish, balance: 50);
    expect(pet.coinsSpent, fish.price);
    expect(pet.inventory['fish'], 1);
    expect(pet.balance(0), adoptionGift - fish.price);
  });

  test('cannot buy without enough coins or for the wrong pet', () {
    expect(() => buy(fresh(), itemById('fish')!, balance: 1),
        throwsA(isA<PetActionError>()));
    expect(() => buy(fresh(PetSpecies.dog), itemById('fish')!, balance: 99),
        throwsA(isA<PetActionError>()));
  });

  test('feeding uses one item and fills the need, capped at 100', () {
    final fish = itemById('fish')!;
    var pet = buy(buy(fresh(), fish, balance: 99), fish, balance: 99);
    pet = use(pet, fish);
    expect(pet.inventory['fish'], 1);
    expect(pet.need(PetNeed.food), 100, reason: '80 + 35 capped');
    pet = use(pet, fish);
    expect(pet.inventory.containsKey('fish'), isFalse);
    expect(() => use(pet, fish), throwsA(isA<PetActionError>()));
  });

  test('a hungry pet bounces back after a meal', () {
    final fish = itemById('fish')!;
    var pet = buy(fresh(), fish, balance: 99)
        .decayed(t0.add(const Duration(hours: 20)));
    expect(pet.need(PetNeed.food), lessThan(lowNeed));
    pet = use(pet, fish);
    expect(pet.need(PetNeed.food), greaterThan(lowNeed));
  });

  test('nextLow reports the need that runs out first', () {
    final next = fresh().nextLow();
    expect(next.need, PetNeed.water, reason: 'water drains fastest');
    expect(next.at.isAfter(t0), isTrue);
  });

  test('round-trips through JSON', () {
    final pet = buy(fresh(PetSpecies.panda), itemById('bamboo')!, balance: 99);
    final back = PetState.fromJson(pet.toJson())!;
    expect(back.species, PetSpecies.panda);
    expect(back.inventory, pet.inventory);
    expect(back.coinsSpent, pet.coinsSpent);
    expect(back.need(PetNeed.food), pet.need(PetNeed.food));
  });
}
