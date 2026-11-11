import 'package:flutter_test/flutter_test.dart';
import 'package:roadmap_x/core/gamification/progress_engine.dart';

void main() {
  DayActivity day(int habitsDue, int habitsDone, int tasksDone) => DayActivity(
        day: DateTime(2026, 11, 1),
        habitsDue: habitsDue,
        habitsDone: habitsDone,
        tasksDone: tasksDone,
      );

  group('levels', () {
    test('thresholds grow by 100 per level', () {
      expect(xpToReach(1), 0);
      expect(xpToReach(2), 100);
      expect(xpToReach(3), 300);
      expect(xpToReach(4), 600);
    });

    test('levelFor places XP in the right band', () {
      expect(levelFor(0).level, 1);
      expect(levelFor(99).level, 1);
      expect(levelFor(100).level, 2);
      final l = levelFor(450);
      expect(l.level, 3);
      expect(l.xpIntoLevel, 150);
      expect(l.xpForLevel, 300);
      expect(l.title, 'Pathfinder');
    });

    test('growth stage follows level', () {
      expect(levelFor(0).stage, 0);
      expect(levelFor(xpToReach(3)).stage, 1);
      expect(levelFor(xpToReach(6)).stage, 2);
      expect(levelFor(xpToReach(10)).stage, 3);
    });
  });

  test('XP adds up every kind of progress', () {
    expect(
      computeXp(
        habitTicks: 3,
        tasksDone: 2,
        perfectDays: 1,
        milestonesDone: 1,
        goalsDone: 0,
      ),
      3 * 10 + 2 * 15 + 50 + 100,
    );
  });

  group('health', () {
    test('a new companion starts healthy', () {
      expect(computeHealth(const []), HealthRules.start);
    });

    test('empty days cost health, active days restore it', () {
      expect(computeHealth([day(2, 0, 0)]), 60);
      expect(computeHealth([day(2, 0, 0), day(2, 0, 0)]), 40);
      expect(computeHealth([day(2, 0, 0), day(2, 2, 0)]), 75,
          reason: 'a perfect day heals 15');
      expect(computeHealth([day(4, 1, 0)]), 84, reason: 'some activity +4');
      expect(computeHealth([day(4, 1, 2)]), 88, reason: '3+ done is +8');
    });

    test('never drops below zero or above 100, and never dies', () {
      expect(computeHealth(List.filled(10, day(1, 0, 0))), 0);
      expect(computeHealth(List.filled(10, day(1, 1, 0))), 100);
      final recovering = [...List.filled(10, day(1, 0, 0)), day(1, 1, 0)];
      expect(computeHealth(recovering), 15, reason: 'one good day helps');
    });
  });

  group('mood', () {
    test('follows health', () {
      expect(moodFor(90, doneToday: false, perfectToday: false),
          CompanionMood.happy);
      expect(moodFor(65, doneToday: false, perfectToday: false),
          CompanionMood.content);
      expect(moodFor(45, doneToday: false, perfectToday: false),
          CompanionMood.bored);
      expect(moodFor(25, doneToday: false, perfectToday: false),
          CompanionMood.tired);
      expect(moodFor(5, doneToday: false, perfectToday: false),
          CompanionMood.sick);
    });

    test('lifts the moment something is done today', () {
      expect(moodFor(70, doneToday: false, perfectToday: true),
          CompanionMood.happy);
      expect(moodFor(57, doneToday: true, perfectToday: false),
          CompanionMood.content);
    });
  });
}
