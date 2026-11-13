import 'package:flutter_test/flutter_test.dart';
import 'package:roadmap_x/features/goals/domain/goal_pace.dart';

void main() {
  final start = DateTime(2026, 1, 1);
  final target = DateTime(2026, 4, 11); // 100 days
  GoalPace pace(int total, int done, DateTime now, {DateTime? last}) =>
      GoalPace.compute(
        createdAt: start,
        targetDate: target,
        totalTasks: total,
        doneTasks: done,
        lastActivity: last,
        now: now,
      );

  test('on track when work keeps up with time', () {
    final p = pace(20, 10, DateTime(2026, 2, 20)); // 50% time, 50% done
    expect(p.status, PaceStatus.onTrack);
    expect(p.tasksPerWeek, greaterThan(0));
    expect(p.summary, startsWith('On track'));
  });

  test('behind, with the weekly rate needed', () {
    final p = pace(20, 4, DateTime(2026, 2, 20)); // 50% time, 20% done
    expect(p.status, PaceStatus.behind);
    // 16 left over 50 days (~7.3 weeks) → 3 a week.
    expect(p.tasksPerWeek, 3);
    expect(p.summary, contains('3 tasks/week'));
  });

  test('ahead, done, overdue and no tasks', () {
    expect(pace(10, 8, DateTime(2026, 2, 1)).status, PaceStatus.ahead);
    expect(pace(10, 10, DateTime(2026, 2, 1)).status, PaceStatus.done);
    expect(pace(10, 3, DateTime(2026, 5, 1)).status, PaceStatus.overdue);
    expect(pace(0, 0, DateTime(2026, 2, 1)).status, PaceStatus.noTasks);
  });

  test('days since the last completed task', () {
    final p =
        pace(10, 2, DateTime(2026, 2, 20), last: DateTime(2026, 2, 10, 18));
    expect(p.staleDays, 10);
    expect(pace(10, 0, DateTime(2026, 1, 9)).staleDays, 8,
        reason: 'nothing done yet: counts from creation');
  });
}
