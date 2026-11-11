/// The rules behind XP, levels and the companion's health.
///
/// Everything here is a pure function of the user's history. Nothing is
/// stored: XP and health are recalculated from check-ins and completed tasks,
/// which already sync, so they are identical on every device, existing users
/// start with the XP they have already earned, and undoing a tick undoes its
/// reward.
library;

/// One calendar day of activity.
class DayActivity {
  const DayActivity({
    required this.day,
    required this.habitsDue,
    required this.habitsDone,
    required this.tasksDone,
  });

  final DateTime day;
  final int habitsDue;
  final int habitsDone;
  final int tasksDone;

  int get done => habitsDone + tasksDone;
  bool get anyDone => done > 0;

  /// Something was done and every habit due that day was ticked.
  bool get isPerfect => anyDone && habitsDone >= habitsDue;
}

class XpRules {
  const XpRules._();
  static const habit = 10;
  static const task = 15;
  static const perfectDay = 50;
  static const milestone = 100;
  static const goal = 500;
}

int computeXp({
  required int habitTicks,
  required int tasksDone,
  required int perfectDays,
  required int milestonesDone,
  required int goalsDone,
}) =>
    habitTicks * XpRules.habit +
    tasksDone * XpRules.task +
    perfectDays * XpRules.perfectDay +
    milestonesDone * XpRules.milestone +
    goalsDone * XpRules.goal;

class LevelInfo {
  const LevelInfo({
    required this.level,
    required this.title,
    required this.xp,
    required this.levelStartXp,
    required this.nextLevelXp,
  });

  final int level;
  final String title;
  final int xp;
  final int levelStartXp;
  final int nextLevelXp;

  int get xpIntoLevel => xp - levelStartXp;
  int get xpForLevel => nextLevelXp - levelStartXp;
  double get progress =>
      xpForLevel == 0 ? 0 : (xpIntoLevel / xpForLevel).clamp(0.0, 1.0);

  /// 0 seedling … 3 fully grown; drives how big the companion looks.
  int get stage => switch (level) {
        <= 2 => 0,
        <= 5 => 1,
        <= 9 => 2,
        _ => 3,
      };
}

/// Total XP needed to reach [level]: 0, 100, 300, 600, 1000, … Each level
/// asks for 100 more than the last, so early levels come quickly.
int xpToReach(int level) => 50 * level * (level - 1);

String levelTitle(int level) => switch (level) {
      <= 2 => 'Explorer',
      <= 5 => 'Pathfinder',
      <= 9 => 'Navigator',
      <= 14 => 'Trailblazer',
      _ => 'Legend',
    };

LevelInfo levelFor(int xp) {
  var level = 1;
  while (xpToReach(level + 1) <= xp) {
    level++;
  }
  return LevelInfo(
    level: level,
    title: levelTitle(level),
    xp: xp,
    levelStartXp: xpToReach(level),
    nextLevelXp: xpToReach(level + 1),
  );
}

class HealthRules {
  const HealthRules._();
  static const start = 80;
  static const perfectDay = 15;
  static const busyDay = 8; // 3 or more things done
  static const someDay = 4; // 1–2 things done
  static const emptyDay = -20; // nothing done
  static const busyThreshold = 3;
}

/// Health after the given finished days, oldest first. Today is never
/// included: the day is not over, so it cannot be held against anyone yet.
///
/// The companion never dies. At worst it is sick, and a single perfect day
/// visibly brings it back.
int computeHealth(Iterable<DayActivity> finishedDays) {
  var health = HealthRules.start;
  for (final d in finishedDays) {
    if (d.isPerfect) {
      health += HealthRules.perfectDay;
    } else if (d.done >= HealthRules.busyThreshold) {
      health += HealthRules.busyDay;
    } else if (d.anyDone) {
      health += HealthRules.someDay;
    } else {
      health += HealthRules.emptyDay;
    }
    health = health.clamp(0, 100);
  }
  return health;
}

enum CompanionMood { happy, content, bored, tired, sick }

extension CompanionMoodLabel on CompanionMood {
  String get label => switch (this) {
        CompanionMood.happy => 'Happy',
        CompanionMood.content => 'Content',
        CompanionMood.bored => 'Bored',
        CompanionMood.tired => 'Tired',
        CompanionMood.sick => 'Unwell',
      };
}

/// Mood follows health, lifted by what has already been done today so the
/// companion reacts the moment something is ticked.
CompanionMood moodFor(
  int health, {
  required bool doneToday,
  required bool perfectToday,
}) {
  final effective = health + (perfectToday ? 15 : (doneToday ? 5 : 0));
  if (effective >= 80) return CompanionMood.happy;
  if (effective >= 60) return CompanionMood.content;
  if (effective >= 40) return CompanionMood.bored;
  if (effective >= 20) return CompanionMood.tired;
  return CompanionMood.sick;
}
