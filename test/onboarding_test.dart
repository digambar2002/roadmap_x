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

/// The welcome screen's job is to ask the data question before any data
/// exists, which is the only point at which it is cheap to answer.
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
            path: '/dashboard',
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

  testWidgets('offers both paths on a first run', (tester) async {
    await pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Start fresh'), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);
  });

  testWidgets('"start fresh" completes onboarding and opens the app',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('Start fresh'));
    await tester.pumpAndSettle();

    expect(Onboarding.isComplete(prefs), isTrue);
    expect(find.text('dashboard'), findsOneWidget);
  });

  testWidgets('"I already have an account" goes to sign-in', (tester) async {
    await pump(tester);
    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();

    expect(Onboarding.isComplete(prefs), isTrue);
    expect(find.text('account'), findsOneWidget);
  });

  testWidgets('hides the sign-in path when no backend is configured',
      (tester) async {
    await pump(tester, syncConfigured: false);
    expect(find.text('Start fresh'), findsOneWidget);
    expect(find.text('I already have an account'), findsNothing,
        reason: 'there is nothing to sign in to');
  });

  testWidgets('the redirect holds the app on welcome until answered',
      (tester) async {
    await pump(tester);
    expect(find.text('Start fresh'), findsOneWidget);
    expect(find.text('dashboard'), findsNothing);
  });

  test('an already-answered device goes straight through', () async {
    await Onboarding.markComplete(prefs);
    expect(Onboarding.isComplete(prefs), isTrue);
  });
}
