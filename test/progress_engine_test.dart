import 'package:flutter_test/flutter_test.dart';
import 'package:roadmap_x/core/gamification/progress_engine.dart';

void main() {
  test('a perfect day needs activity and every due habit', () {
    DayActivity d(int due, int done, int tasks) => DayActivity(
          day: DateTime(2026, 11, 1),
          habitsDue: due,
          habitsDone: done,
          tasksDone: tasks,
        );
    expect(d(2, 2, 0).isPerfect, isTrue);
    expect(d(2, 1, 3).isPerfect, isFalse);
    expect(d(0, 0, 0).isPerfect, isFalse);
    expect(d(0, 0, 1).isPerfect, isTrue);
  });

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

}
