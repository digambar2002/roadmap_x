/// The rules behind XP and levels.
///
/// Everything here is a pure function of the user's history. Nothing is
/// stored: XP is recalculated from check-ins and completed tasks, which
/// already sync, so it is identical on every device, existing users start
/// with the XP they have already earned, and undoing a tick undoes its
/// reward. Coins for the pet store are derived from XP.
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

  /// Per focused minute: a 25-minute session is worth 25 XP (5 coins).
  static const focusMinute = 1;
}

int computeXp({
  required int habitTicks,
  required int tasksDone,
  required int perfectDays,
  required int milestonesDone,
  required int goalsDone,
  int focusMinutes = 0,
}) =>
    habitTicks * XpRules.habit +
    tasksDone * XpRules.task +
    perfectDays * XpRules.perfectDay +
    milestonesDone * XpRules.milestone +
    goalsDone * XpRules.goal +
    focusMinutes * XpRules.focusMinute;

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
