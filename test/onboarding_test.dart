import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roadmap_x/core/services/onboarding.dart';
import 'package:roadmap_x/core/services/shared_preferences_provider.dart';
import 'package:roadmap_x/core/sync/account_service.dart';
import 'package:roadmap_x/core/theme/app_theme.dart';
import 'package:roadmap_x/features/onboarding/presentation/welcome_screen.dart';
import 'package:roadmap_x/features/premium/providers/premium_provider.dart';

/// The welcome screen introduces the app and takes a name; signing in is an
/// offer on the last page, not a question that blocks entry.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> pump(
    WidgetTester tester, {
    bool syncConfigured = true,
  }) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/welcome',
      redirect: (context, state) {
        if (Onboarding.isComplete(prefs)) return null;
        const allowed = {'/welcome', '/premium'};
        if (allowed.contains(state.matchedLocation)) return null;
        return '/welcome';
      },
      routes: [
        GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
        GoRoute(
            path: '/today',
            builder: (_, __) => const Scaffold(body: Text('dashboard'))),
        GoRoute(
            path: '/premium',
            builder: (_, __) => const Scaffold(body: Text('account'))),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          accountProvider.overrideWith(
            (ref) => Stream.value(
              AccountState(
                isConfigured: syncConfigured,
                isSignedIn: false,
                isPremium: false,
              ),
            ),
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> skipToSetup(WidgetTester tester) async {
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
  }

  testWidgets('walks through the intro slides to the set-up page',
      (tester) async {
    await pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Goals that go somewhere'), findsOneWidget);
    expect(find.text('Get started'), findsNothing);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Habits and a daily rhythm'), findsOneWidget);

    await skipToSetup(tester);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Sign in with email'), findsOneWidget);
  });

  testWidgets('"Get started" saves the name, completes onboarding and opens '
      'the app', (tester) async {
    await pump(tester);
    await skipToSetup(tester);
    await tester.enterText(find.byType(TextField), 'Dee');
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(Onboarding.isComplete(prefs), isTrue);
    expect(prefs.getString('user_name'), 'Dee');
    expect(find.text('dashboard'), findsOneWidget);
  });

  testWidgets('"Sign in with email" goes to the account screen',
      (tester) async {
    await pump(tester);
    await skipToSetup(tester);
    await tester.tap(find.text('Sign in with email'));
    await tester.pumpAndSettle();

    expect(Onboarding.isComplete(prefs), isTrue);
    expect(find.text('account'), findsOneWidget);
  });

  testWidgets('hides the account options when no backend is configured',
      (tester) async {
    await pump(tester, syncConfigured: false);
    await skipToSetup(tester);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing,
        reason: 'there is nothing to sign in to');
    expect(find.text('Sign in with email'), findsNothing);
  });

  testWidgets('the redirect holds the app on welcome until answered',
      (tester) async {
    await pump(tester);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('dashboard'), findsNothing);
  });

  test('an already-answered device goes straight through', () async {
    await Onboarding.markComplete(prefs);
    expect(Onboarding.isComplete(prefs), isTrue);
  });
}
