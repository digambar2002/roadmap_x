import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:roadmap_x/core/ai/ai_access.dart';
import 'package:roadmap_x/core/models/models.dart';
import 'package:roadmap_x/features/goals/providers/goal_provider.dart';
import 'package:roadmap_x/features/onboarding/presentation/first_goal_screen.dart';
import 'package:roadmap_x/features/premium/providers/premium_provider.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    AiAccess access = AiAccess.none,
    List<Goal> goals = const [],
  }) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/today',
      routes: [
        GoRoute(
            path: '/today',
            builder: (_, __) => const Scaffold(body: Text('dashboard'))),
        GoRoute(
            path: '/first-goal', builder: (_, __) => const FirstGoalScreen()),
        GoRoute(
            path: '/premium',
            builder: (_, __) => const Scaffold(body: Text('account'))),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        aiAccessProvider.overrideWithValue(access),
        freeAiPlansLeftProvider.overrideWith((ref) async => null),
        syncAvailableProvider.overrideWithValue(true),
        allGoalsProvider.overrideWith((ref) => Stream.value(goals)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    router.push('/first-goal');
    await tester.pumpAndSettle();
  }

  testWidgets('asks what the user wants and offers three ways in',
      (tester) async {
    await pump(tester);
    expect(find.text('What do you want to achieve?'), findsOneWidget);
    expect(find.text('Build my plan'), findsOneWidget);
    expect(find.text('Paste a plan I already have'), findsOneWidget);
    expect(find.text('Start from a template'), findsOneWidget);
    expect(find.text('Free with sign-in: 3 AI plans a month'), findsOneWidget);
  });

  testWidgets('a suggestion fills in the sentence', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Run a 5K'));
    await tester.pump();
    expect(find.textContaining('finishing a 5K in 8 weeks'), findsOneWidget);
  });

  testWidgets('too little text is caught before anything is sent',
      (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'fit');
    await tester.tap(find.text('Build my plan'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Add a little more detail'), findsOneWidget);
  });

  testWidgets('signed out, building offers a free sign-in and keeps the text',
      (tester) async {
    await pump(tester);
    await tester.enterText(
        find.byType(TextField), 'Learn to swim in two months');
    await tester.tap(find.text('Build my plan'));
    await tester.pumpAndSettle();
    expect(find.text('Let AI build your plan, free'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Learn to swim in two months'), findsOneWidget);
  });

  testWidgets('Skip goes to Today', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('dashboard'), findsOneWidget);
  });

  testWidgets('an account that already has goals skips this page',
      (tester) async {
    await pump(tester, goals: [Goal()]);
    expect(find.text('What do you want to achieve?'), findsNothing);
    expect(find.text('dashboard'), findsOneWidget);
  });
}
