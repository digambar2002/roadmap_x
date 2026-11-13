import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:roadmap_x/core/services/shared_preferences_provider.dart';
import 'package:roadmap_x/features/habits/providers/habit_provider.dart';
import 'package:roadmap_x/features/pet/providers/pet_provider.dart';
import 'package:roadmap_x/features/ritual/presentation/ritual_sheets.dart';
import 'package:roadmap_x/features/tasks/providers/task_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roadmap_x/features/ritual/data/day_journal.dart';
import 'package:roadmap_x/features/ritual/presentation/ritual_today.dart';

void main() {
  final morning = DateTime(2026, 11, 13, 8, 30);
  final noon = DateTime(2026, 11, 13, 15);
  final evening = DateTime(2026, 11, 13, 20);

  test('mornings offer planning, evenings the wrap-up, afternoons nothing', () {
    const empty = DayJournal();
    expect(ritualDue(empty, morning), RitualKind.plan);
    expect(ritualDue(empty, noon), isNull);
    expect(ritualDue(empty, evening), RitualKind.wrapUp);
  });

  test('a done ritual is not offered again that day', () {
    final key = DayJournal.dayKey(morning);
    final journal = DayJournal(
      plans: {
        key: const ['t1']
      },
      notes: {key: DayNote(mood: 4, note: 'good', at: evening)},
    );
    expect(ritualDue(journal, morning), isNull);
    expect(ritualDue(journal, evening), isNull);
    expect(journal.topFor(morning), ['t1']);
  });

  test('the journal round-trips through preferences', () async {
    final key = DayJournal.dayKey(morning);
    final journal = DayJournal(
      plans: {
        key: const ['a', 'b']
      },
      notes: {key: DayNote(mood: 5, note: 'Shipped it', at: evening)},
    );
    SharedPreferences.setMockInitialValues(
        {DayJournal.key: jsonEncode(journal.toJson())});
    final back = DayJournal.read(await SharedPreferences.getInstance());
    expect(back.topFor(morning), ['a', 'b']);
    expect(back.noteFor(morning)!.mood, 5);
    expect(back.noteFor(morning)!.note, 'Shipped it');
    expect(back.hasWrappedUp(morning), isTrue);
  });

  test('a corrupt journal reads as empty instead of crashing', () async {
    SharedPreferences.setMockInitialValues({DayJournal.key: '{not json'});
    final back = DayJournal.read(await SharedPreferences.getInstance());
    expect(back.plans, isEmpty);
  });

  testWidgets('wrap-up asks for a mood before saving', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        todayTasksGroupedProvider
            .overrideWith((ref) async => const TodayTasksData(
                  overdue: [],
                  dueToday: [],
                  thisWeek: [],
                  noDueDate: [],
                )),
        todayHabitChecksProvider.overrideWith(_NoChecks.new),
        petViewProvider.overrideWithValue(null),
      ],
      child: const MaterialApp(home: Scaffold(body: WrapUpSheet())),
    ));
    await tester.pump();
    await tester.tap(find.text('Wrap up'));
    await tester.pump();
    expect(find.textContaining('Pick a face'), findsOneWidget);
    for (final face in moodFaces) {
      expect(find.text(face), findsOneWidget);
    }
  });
}

class _NoChecks extends TodayHabitChecksNotifier {
  @override
  Future<Set<String>> build() async => {};
}
