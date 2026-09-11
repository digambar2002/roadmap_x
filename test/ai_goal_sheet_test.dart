import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roadmap_x/core/services/shared_preferences_provider.dart';
import 'package:roadmap_x/core/theme/app_theme.dart';
import 'package:roadmap_x/features/ai_goal/presentation/ai_goal_sheet.dart';

/// The AI goal sheet's root Column uses an Expanded, which needs a bounded
/// height. A bottom sheet supplies one; a dialog has to be made to.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> openSheet(
    WidgetTester tester,
    Size window, {
    bool withApiKey = false,
  }) async {
    if (withApiKey) {
      await prefs.setString('gemini_api_key', 'test-key');
    }
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showAiGoalSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const Scaffold(body: Text('settings')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp.router(
          theme: AppTheme.dark,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('opens as a bottom sheet on a phone window', (tester) async {
    await openSheet(tester, const Size(430, 932));
    expect(tester.takeException(), isNull);
    expect(find.byType(AiGoalSheet), findsOneWidget);
  });

  testWidgets('opens as a dialog on a desktop window', (tester) async {
    await openSheet(tester, const Size(1280, 860));
    expect(tester.takeException(), isNull);
    expect(find.byType(AiGoalSheet), findsOneWidget);
  });

  testWidgets('the dialog is actually visible, not zero-height',
      (tester) async {
    await openSheet(tester, const Size(1280, 860));
    final size = tester.getSize(find.byType(AiGoalSheet));
    expect(size.height, greaterThan(200),
        reason: 'a collapsed sheet reads to the user as a blank screen');
    expect(size.width, greaterThan(200));
  });

  testWidgets('opens as a dialog with an API key configured', (tester) async {
    await openSheet(tester, const Size(1280, 860), withApiKey: true);
    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.byType(AiGoalSheet));
    expect(size.height, greaterThan(200));
  });

  testWidgets('opens as a bottom sheet with an API key configured',
      (tester) async {
    await openSheet(tester, const Size(430, 932), withApiKey: true);
    expect(tester.takeException(), isNull);
  });
}
