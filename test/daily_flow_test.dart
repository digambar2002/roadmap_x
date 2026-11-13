import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roadmap_x/core/db/isar_service.dart';
import 'package:roadmap_x/core/gamification/gamification_service.dart';
import 'package:roadmap_x/core/models/models.dart';
import 'package:roadmap_x/core/services/shared_preferences_provider.dart';
import 'package:roadmap_x/features/focus/data/focus_sessions.dart';
import 'package:roadmap_x/features/ritual/data/day_journal.dart';
import 'package:roadmap_x/features/ritual/presentation/ritual_sheets.dart';
import 'package:roadmap_x/features/tasks/data/task_repository.dart';
import 'package:roadmap_x/features/tasks/presentation/quick_add_task_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Isar isar;
  late SharedPreferences prefs;

  setUpAll(() async => Isar.initializeIsarCore(download: true));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    dir = await Directory.systemTemp.createTemp('roadmapx_daily');
    isar = await Isar.open(
      [
        GoalSchema,
        MilestoneSchema,
        TaskSchema,
        ScheduleItemSchema,
        HabitSchema,
        HabitCheckinSchema,
        ScheduleCompletionSchema,
        AppSettingSchema,
      ],
      directory: dir.path,
      name: 'daily_${dir.path.hashCode}',
    );
    IsarService.instance.overrideForTesting(isar);
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<List<Task>> openTasks() =>
      isar.tasks.filter().deletedAtIsNull().isCompletedEqualTo(false).findAll();

  /// Runs [action] in real time and waits until [done] holds.
  Future<void> realTime(WidgetTester tester, Future<void> Function() action,
      Future<bool> Function() done) async {
    await tester.runAsync(() async {
      await action();
      for (var i = 0; i < 100 && !await done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();
  }

  group('focus sessions', () {
    test('count toward XP, today\'s minutes, and settle after a closed app',
        () async {
      final before = (await GamificationService.instance.load()).level.xp;
      await FocusSessions.instance
          .add(FocusSession(start: DateTime.now(), minutes: 25));
      final after = await GamificationService.instance.load();
      expect(after.level.xp - before, 25, reason: '1 XP per focused minute');
      expect(after.focusMinutesToday, 25);

      // A session that ran out while the app was closed.
      final start = DateTime.now().subtract(const Duration(minutes: 30));
      await FocusSessions.instance.setRunning(RunningFocus(
        start: start,
        endAt: start.add(const Duration(minutes: 15)),
        minutes: 15,
      ));
      final credited = await FocusSessions.instance.settleRunning();
      expect(credited?.minutes, 15);
      expect(await FocusSessions.instance.running(), isNull);
      expect(await FocusSessions.instance.minutesOn(DateTime.now()), 40);
    });

    test('a session still running is not credited early', () async {
      await FocusSessions.instance.setRunning(RunningFocus(
        start: DateTime.now(),
        endAt: DateTime.now().add(const Duration(minutes: 20)),
        minutes: 20,
      ));
      expect(await FocusSessions.instance.settleRunning(), isNull);
      expect(await FocusSessions.instance.running(), isNotNull);
    });
  });

  testWidgets('quick capture: type, Enter, type the next — all into the Inbox',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: Scaffold(body: QuickAddTaskSheet())),
    ));
    await tester.enterText(find.byType(TextField), 'Call the bank');
    await realTime(
        tester,
        () => tester.testTextInput.receiveAction(TextInputAction.next),
        () async => (await openTasks()).isNotEmpty);
    expect(find.textContaining('Added "Call the bank"'), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text, '',
        reason: 'cleared for the next one');

    await tester.enterText(find.byType(TextField), 'Buy milk');
    await realTime(
        tester,
        () => tester.testTextInput.receiveAction(TextInputAction.next),
        () async => (await openTasks()).length == 2);

    final tasks = await tester.runAsync(openTasks);
    expect(tasks!.map((t) => t.text).toSet(), {'Call the bank', 'Buy milk'});
    expect(tasks.every((t) => t.milestoneUid == ''), isTrue, reason: 'Inbox');
    final now = DateTime.now();
    expect(tasks.first.dueDate, DateTime(now.year, now.month, now.day),
        reason: 'defaults to today');
  });

  test("plan the day: picked tasks move to today and become the top 3",
      () async {
    final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 3);
    final a = await TaskRepository.instance
        .create(text: 'Write report', dueDate: next);
    final b = await TaskRepository.instance.create(text: 'Gym session');
    final candidates = await TaskRepository.instance.getActiveTaskContexts();

    await startDay(container.read(dayJournalProvider.notifier),
        picked: [a.uid, b.uid], candidates: candidates);

    expect(container.read(dayJournalProvider).topFor(now), [a.uid, b.uid]);
    final today = DateTime(now.year, now.month, now.day);
    for (final t in await openTasks()) {
      expect(t.dueDate, today, reason: '${t.text} moved to today');
    }
    // Reading the journal back from preferences gives the same plan.
    expect(DayJournal.read(prefs).topFor(now), [a.uid, b.uid]);
  });

  test('wrap up: unfinished tasks roll to tomorrow and the mood is saved',
      () async {
    final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final t = await TaskRepository.instance
        .create(text: 'Unfinished', dueDate: today);

    await wrapUpDay(container.read(dayJournalProvider.notifier),
        mood: 4, note: 'Good day', rollTaskIds: [t.id]);

    final note = container.read(dayJournalProvider).noteFor(now)!;
    expect(note.mood, 4);
    expect(note.note, 'Good day');
    expect((await openTasks()).single.dueDate,
        DateTime(today.year, today.month, today.day + 1));
  });
}
