/// The virtual pet: five species, a store, four needs that drain over real
/// time, and coins earned from XP.
///
/// The loop is deliberate: productive days earn XP, XP earns coins, coins buy
/// food and supplies, and a pet that is not fed gets hungry, thirsty, bored
/// and dirty. It never dies — at worst it is unwell, and one good meal
/// visibly brings it back.
library;

import 'dart:ui' show Color;

// ── Species ───────────────────────────────────────────────

enum PetSpecies { cat, dog, bunny, panda, dino }

class SpeciesInfo {
  const SpeciesInfo({
    required this.label,
    required this.defaultName,
    required this.body,
    required this.belly,
    required this.accent,
    required this.blurb,
  });

  final String label;
  final String defaultName;
  final Color body;
  final Color belly;
  final Color accent;
  final String blurb;
}

const speciesInfo = <PetSpecies, SpeciesInfo>{
  PetSpecies.cat: SpeciesInfo(
    label: 'Cat',
    defaultName: 'Mochi',
    body: Color(0xFFF4A261),
    belly: Color(0xFFFFE8D1),
    accent: Color(0xFFF8A5B6),
    blurb: 'Curious and cuddly. Loves fish and yarn.',
  ),
  PetSpecies.dog: SpeciesInfo(
    label: 'Puppy',
    defaultName: 'Biscuit',
    body: Color(0xFFC08552),
    belly: Color(0xFFF3DFC8),
    accent: Color(0xFF8C5A35),
    blurb: 'Loyal and full of energy. Lives for fetch.',
  ),
  PetSpecies.bunny: SpeciesInfo(
    label: 'Bunny',
    defaultName: 'Clover',
    body: Color(0xFFE9E4F2),
    belly: Color(0xFFFFFFFF),
    accent: Color(0xFFF7A8C4),
    blurb: 'Gentle and bouncy. Carrots, please.',
  ),
  PetSpecies.panda: SpeciesInfo(
    label: 'Panda',
    defaultName: 'Bamboo',
    body: Color(0xFFF7F7F7),
    belly: Color(0xFFFFFFFF),
    accent: Color(0xFF2B2B2B),
    blurb: 'Calm and snack-motivated. Bamboo all day.',
  ),
  PetSpecies.dino: SpeciesInfo(
    label: 'Dino',
    defaultName: 'Rex',
    body: Color(0xFF6CC48A),
    belly: Color(0xFFDDF5C9),
    accent: Color(0xFF3E9A60),
    blurb: 'Small, mighty and always hungry.',
  ),
};

// ── Needs ─────────────────────────────────────────────────

enum PetNeed { food, water, fun, clean }

extension PetNeedInfo on PetNeed {
  String get label => switch (this) {
        PetNeed.food => 'Food',
        PetNeed.water => 'Water',
        PetNeed.fun => 'Fun',
        PetNeed.clean => 'Clean',
      };

  String get emoji => switch (this) {
        PetNeed.food => '🍖',
        PetNeed.water => '💧',
        PetNeed.fun => '🎾',
        PetNeed.clean => '🫧',
      };

  /// What the pet says when this need is the lowest and running out.
  String get complaint => switch (this) {
        PetNeed.food => 'hungry',
        PetNeed.water => 'thirsty',
        PetNeed.fun => 'bored',
        PetNeed.clean => 'dirty',
      };

  /// Points lost per hour. Tuned so one active day of habits and tasks earns
  /// enough coins to cover a day of care, with some left over for treats.
  double get decayPerHour => switch (this) {
        PetNeed.food => 3.0,
        PetNeed.water => 3.5,
        PetNeed.fun => 2.0,
        PetNeed.clean => 1.5,
      };
}

/// Below this a need counts as urgent: the pet complains and nudges.
const lowNeed = 25.0;

// ── Store ─────────────────────────────────────────────────

enum ItemCategory { food, drink, toy, care }

class StoreItem {
  const StoreItem({
    required this.id,
    required this.name,
    required this.emoji,
    required this.price,
    required this.category,
    required this.effects,
    this.species,
  });

  final String id;
  final String name;
  final String emoji;
  final int price;
  final ItemCategory category;

  /// Points added to each need when used.
  final Map<PetNeed, double> effects;

  /// Who can use it. Null means every pet.
  final Set<PetSpecies>? species;

  bool suits(PetSpecies s) => species == null || species!.contains(s);
}

const storeItems = <StoreItem>[
  // Shared basics.
  StoreItem(
    id: 'water',
    name: 'Fresh water',
    emoji: '💧',
    price: 3,
    category: ItemCategory.drink,
    effects: {PetNeed.water: 40},
  ),
  StoreItem(
    id: 'juice',
    name: 'Fruit juice',
    emoji: '🧃',
    price: 6,
    category: ItemCategory.drink,
    effects: {PetNeed.water: 50, PetNeed.fun: 10},
  ),
  StoreItem(
    id: 'soap',
    name: 'Bubble bath',
    emoji: '🧼',
    price: 4,
    category: ItemCategory.care,
    effects: {PetNeed.clean: 55},
  ),
  StoreItem(
    id: 'medicine',
    name: 'Vitamins',
    emoji: '💊',
    price: 15,
    category: ItemCategory.care,
    effects: {
      PetNeed.food: 15,
      PetNeed.water: 15,
      PetNeed.fun: 15,
      PetNeed.clean: 15,
    },
  ),
  StoreItem(
    id: 'ball',
    name: 'Bouncy ball',
    emoji: '⚽',
    price: 8,
    category: ItemCategory.toy,
    effects: {PetNeed.fun: 35},
  ),
  // Cat.
  StoreItem(
    id: 'fish',
    name: 'Fish',
    emoji: '🐟',
    price: 5,
    category: ItemCategory.food,
    effects: {PetNeed.food: 35},
    species: {PetSpecies.cat},
  ),
  StoreItem(
    id: 'milk',
    name: 'Milk',
    emoji: '🥛',
    price: 4,
    category: ItemCategory.drink,
    effects: {PetNeed.water: 30, PetNeed.food: 10},
    species: {PetSpecies.cat},
  ),
  StoreItem(
    id: 'yarn',
    name: 'Yarn ball',
    emoji: '🧶',
    price: 9,
    category: ItemCategory.toy,
    effects: {PetNeed.fun: 45},
    species: {PetSpecies.cat},
  ),
  // Dog.
  StoreItem(
    id: 'bone',
    name: 'Bone',
    emoji: '🦴',
    price: 5,
    category: ItemCategory.food,
    effects: {PetNeed.food: 30, PetNeed.fun: 10},
    species: {PetSpecies.dog},
  ),
  StoreItem(
    id: 'steak',
    name: 'Steak',
    emoji: '🥩',
    price: 9,
    category: ItemCategory.food,
    effects: {PetNeed.food: 55},
    species: {PetSpecies.dog, PetSpecies.dino},
  ),
  StoreItem(
    id: 'frisbee',
    name: 'Frisbee',
    emoji: '🥏',
    price: 9,
    category: ItemCategory.toy,
    effects: {PetNeed.fun: 45},
    species: {PetSpecies.dog},
  ),
  // Bunny.
  StoreItem(
    id: 'carrot',
    name: 'Carrot',
    emoji: '🥕',
    price: 4,
    category: ItemCategory.food,
    effects: {PetNeed.food: 30},
    species: {PetSpecies.bunny},
  ),
  StoreItem(
    id: 'lettuce',
    name: 'Lettuce',
    emoji: '🥬',
    price: 5,
    category: ItemCategory.food,
    effects: {PetNeed.food: 30, PetNeed.water: 10},
    species: {PetSpecies.bunny, PetSpecies.dino},
  ),
  // Panda.
  StoreItem(
    id: 'bamboo',
    name: 'Bamboo',
    emoji: '🎋',
    price: 5,
    category: ItemCategory.food,
    effects: {PetNeed.food: 35},
    species: {PetSpecies.panda},
  ),
  StoreItem(
    id: 'dumpling',
    name: 'Dumplings',
    emoji: '🥟',
    price: 8,
    category: ItemCategory.food,
    effects: {PetNeed.food: 45, PetNeed.fun: 5},
    species: {PetSpecies.panda},
  ),
  // Shared treats.
  StoreItem(
    id: 'apple',
    name: 'Apple',
    emoji: '🍎',
    price: 4,
    category: ItemCategory.food,
    effects: {PetNeed.food: 20, PetNeed.water: 10},
    species: {PetSpecies.bunny, PetSpecies.panda, PetSpecies.dino},
  ),
  StoreItem(
    id: 'meat',
    name: 'Drumstick',
    emoji: '🍗',
    price: 6,
    category: ItemCategory.food,
    effects: {PetNeed.food: 40},
    species: {PetSpecies.dino, PetSpecies.cat, PetSpecies.dog},
  ),
];

StoreItem? itemById(String id) {
  for (final item in storeItems) {
    if (item.id == id) return item;
  }
  return null;
}

// ── Coins ─────────────────────────────────────────────────

/// Every 5 XP is worth one coin. A typical productive day (a few habits, a
/// few tasks, a perfect-day bonus) earns 25–30 coins; a day of care costs
/// about 20.
const xpPerCoin = 5;

/// A welcome gift so a newly adopted pet can be fed straight away.
const adoptionGift = 30;

int coinsEarned(int xp) => xp ~/ xpPerCoin;

// ── Mood ──────────────────────────────────────────────────

enum PetMood { happy, content, sad, tired, unwell }

extension PetMoodLabel on PetMood {
  String get label => switch (this) {
        PetMood.happy => 'Happy',
        PetMood.content => 'Content',
        PetMood.sad => 'Sad',
        PetMood.tired => 'Tired',
        PetMood.unwell => 'Unwell',
      };
}

// ── State ─────────────────────────────────────────────────

/// Everything about the pet that has to be remembered. Coins themselves are
/// not stored: the balance is coins earned from XP, plus the adoption gift,
/// minus [coinsSpent].
class PetState {
  const PetState({
    required this.species,
    required this.name,
    required this.needs,
    required this.updatedAt,
    required this.inventory,
    required this.coinsSpent,
    required this.bonusCoins,
  });

  factory PetState.adopt(PetSpecies species, {String? name, DateTime? now}) =>
      PetState(
        species: species,
        name: name ?? speciesInfo[species]!.defaultName,
        needs: const {
          PetNeed.food: 80,
          PetNeed.water: 80,
          PetNeed.fun: 80,
          PetNeed.clean: 80,
        },
        updatedAt: now ?? DateTime.now(),
        inventory: const {},
        coinsSpent: 0,
        bonusCoins: adoptionGift,
      );

  final PetSpecies species;
  final String name;
  final Map<PetNeed, double> needs;

  /// When [needs] were last brought up to date.
  final DateTime updatedAt;

  /// Item id → how many are owned.
  final Map<String, int> inventory;
  final int coinsSpent;
  final int bonusCoins;

  double need(PetNeed n) => needs[n] ?? 0;

  /// Overall wellbeing, 0–100: the average of the four needs.
  double get health =>
      PetNeed.values.map(need).reduce((a, b) => a + b) / PetNeed.values.length;

  PetMood get mood {
    final h = health;
    if (h >= 75) return PetMood.happy;
    if (h >= 55) return PetMood.content;
    if (h >= 35) return PetMood.sad;
    if (h >= 15) return PetMood.tired;
    return PetMood.unwell;
  }

  /// The most urgent need, or null when nothing is low.
  PetNeed? get urgentNeed {
    PetNeed? worst;
    for (final n in PetNeed.values) {
      if (need(n) < lowNeed && (worst == null || need(n) < need(worst))) {
        worst = n;
      }
    }
    return worst;
  }

  int balance(int xp) => coinsEarned(xp) + bonusCoins - coinsSpent;

  /// Needs drained for the time since [updatedAt]. Pure: call it with the
  /// current time whenever the pet is shown.
  PetState decayed(DateTime now) {
    final hours = now.difference(updatedAt).inSeconds / 3600;
    if (hours <= 0) return this;
    return copyWith(
      needs: {
        for (final n in PetNeed.values)
          n: (need(n) - n.decayPerHour * hours).clamp(0, 100).toDouble(),
      },
      updatedAt: now,
    );
  }

  /// Which need drops below [lowNeed] first, and when. A need that is
  /// already low reports [updatedAt].
  ({PetNeed need, DateTime at}) nextLow() {
    PetNeed first = PetNeed.food;
    DateTime? soonest;
    for (final n in PetNeed.values) {
      final above = need(n) - lowNeed;
      final at = above <= 0
          ? updatedAt
          : updatedAt
              .add(Duration(seconds: (above / n.decayPerHour * 3600).round()));
      if (soonest == null || at.isBefore(soonest)) {
        soonest = at;
        first = n;
      }
    }
    return (need: first, at: soonest!);
  }

  PetState copyWith({
    PetSpecies? species,
    String? name,
    Map<PetNeed, double>? needs,
    DateTime? updatedAt,
    Map<String, int>? inventory,
    int? coinsSpent,
    int? bonusCoins,
  }) =>
      PetState(
        species: species ?? this.species,
        name: name ?? this.name,
        needs: needs ?? this.needs,
        updatedAt: updatedAt ?? this.updatedAt,
        inventory: inventory ?? this.inventory,
        coinsSpent: coinsSpent ?? this.coinsSpent,
        bonusCoins: bonusCoins ?? this.bonusCoins,
      );

  Map<String, dynamic> toJson() => {
        'species': species.name,
        'name': name,
        'needs': {for (final e in needs.entries) e.key.name: e.value},
        'updatedAt': updatedAt.toIso8601String(),
        'inventory': inventory,
        'coinsSpent': coinsSpent,
        'bonusCoins': bonusCoins,
      };

  static PetState? fromJson(Map<String, dynamic> json) {
    try {
      final species = PetSpecies.values.byName(json['species'] as String);
      final rawNeeds = (json['needs'] as Map).cast<String, dynamic>();
      return PetState(
        species: species,
        name: json['name'] as String? ?? speciesInfo[species]!.defaultName,
        needs: {
          for (final n in PetNeed.values)
            n: ((rawNeeds[n.name] as num?) ?? 50).toDouble(),
        },
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        inventory: {
          for (final e in ((json['inventory'] as Map?) ?? const {})
              .cast<String, dynamic>()
              .entries)
            e.key: (e.value as num).toInt(),
        },
        coinsSpent: (json['coinsSpent'] as num?)?.toInt() ?? 0,
        bonusCoins: (json['bonusCoins'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

// ── Actions ───────────────────────────────────────────────

class PetActionError implements Exception {
  const PetActionError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Buys one [item] if [balance] covers it.
PetState buy(PetState state, StoreItem item, {required int balance}) {
  if (!item.suits(state.species)) {
    throw PetActionError('${state.name} can\'t use ${item.name}.');
  }
  if (balance < item.price) {
    throw const PetActionError(
        'Not enough coins yet. Finish a task to earn more.');
  }
  return state.copyWith(
    coinsSpent: state.coinsSpent + item.price,
    inventory: {
      ...state.inventory,
      item.id: (state.inventory[item.id] ?? 0) + 1,
    },
  );
}

/// Uses one owned [item] on the pet: feeds, waters, plays or washes it.
PetState use(PetState state, StoreItem item) {
  final owned = state.inventory[item.id] ?? 0;
  if (owned <= 0) {
    throw PetActionError('No ${item.name} left. Visit the store.');
  }
  if (!item.suits(state.species)) {
    throw PetActionError('${state.name} can\'t use ${item.name}.');
  }
  final inventory = {...state.inventory, item.id: owned - 1}
    ..removeWhere((_, v) => v <= 0);
  return state.copyWith(
    inventory: inventory,
    needs: {
      for (final n in PetNeed.values)
        n: (state.need(n) + (item.effects[n] ?? 0)).clamp(0, 100).toDouble(),
    },
  );
}

/// Petting is free: a small lift in fun, so tapping the pet always does
/// something nice.
PetState pat(PetState state) => state.copyWith(
      needs: {
        ...state.needs,
        PetNeed.fun: (state.need(PetNeed.fun) + 2).clamp(0, 100).toDouble(),
      },
    );
