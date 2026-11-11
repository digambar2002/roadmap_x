import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:roadmap_x/core/models/models.dart';
import 'package:roadmap_x/core/models/today_task.dart';
import 'package:roadmap_x/core/theme/app_theme.dart';
import 'package:roadmap_x/features/dashboard/presentation/widgets/today_tasks_section.dart';
import 'package:roadmap_x/features/tasks/providers/task_provider.dart';

/// Adding or ticking a task fires several refresh signals at once. The list
/// must stay on screen while it reloads; swapping it for a placeholder each
/// time is what made the Today tab flicker.
void main() {
  final reload = StateProvider<int>((_) => 0);

  Task task(int id, String text) => Task()
    ..id = id
    ..uid = 't$id'
    ..text = text
    ..isCompleted = false
    ..priority = 0
    ..sortOrder = id
    ..dueDate = DateTime.now()
    ..note = null
    ..completedAt = null
    ..milestoneUid = ''
    ..createdAt = DateTime(2026, 1, 1)
    ..updatedAt = DateTime(2026, 1, 1);

  testWidgets('keeps the task list visible while it reloads', (tester) async {
    var calls = 0;
    late WidgetRef widgetRef;

    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(
          body: Consumer(builder: (context, ref, _) {
            widgetRef = ref;
            return TodayTasksSection(
              groupedAsync: ref.watch(todayTasksGroupedProvider),
            );
          }),
        ),
      ),
    ]);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        todayTasksGroupedProvider.overrideWith((ref) async {
          ref.watch(reload);
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return TodayTasksData(
            overdue: const [],
            dueToday: [
              TodayTaskContext(task: task(1, 'Write tests')),
              if (calls > 1) TodayTaskContext(task: task(2, 'New task')),
            ],
            thisWeek: const [],
            noDueDate: const [],
          );
        }),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Write tests'), findsOneWidget);

    // A task is added: the provider reloads.
    widgetRef.read(reload.notifier).state++;
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Write tests'), findsOneWidget,
        reason: 'the old list stays up during the reload, no flash');

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('New task'), findsOneWidget);
  });
}
