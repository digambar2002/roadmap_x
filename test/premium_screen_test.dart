import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:roadmap_x/core/sync/account_service.dart';
import 'package:roadmap_x/core/theme/app_theme.dart';
import 'package:roadmap_x/features/premium/presentation/premium_screen.dart';
import 'package:roadmap_x/features/premium/providers/premium_provider.dart';

/// The Premium screen is the one place a user goes to fix a locked feature.
/// It must render something actionable in every account state — including the
/// states that cannot be reached on a developer machine.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(
    WidgetTester tester,
    AccountState state, {
    Size window = const Size(430, 932),
  }) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, __) => const PremiumScreen())],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith((ref) => Stream.value(state)),
        ],
        child: MaterialApp.router(
          theme: AppTheme.dark,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders when no backend is configured', (tester) async {
    await pump(tester, const AccountState.unavailable());
    expect(tester.takeException(), isNull);
    expect(find.textContaining('aren\'t available'), findsOneWidget);
  });

  testWidgets('renders a sign-in form when signed out', (tester) async {
    await pump(
      tester,
      const AccountState(
        isConfigured: true,
        isSignedIn: false,
        isPremium: false,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Your plan, on every device'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Accounts are free'), findsOneWidget);
  });

  testWidgets('renders the activation request when signed in but free',
      (tester) async {
    await pump(
      tester,
      const AccountState(
        isConfigured: true,
        isSignedIn: true,
        isPremium: false,
        email: 'someone@example.com',
        userId: 'u1',
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Upgrade to Premium'), findsOneWidget);
    expect(find.text('Free plan'), findsOneWidget);
    expect(find.text('someone@example.com'), findsOneWidget);
    expect(find.text('Get Premium'), findsOneWidget);
  });

  testWidgets('renders the active card when premium', (tester) async {
    await pump(
      tester,
      const AccountState(
        isConfigured: true,
        isSignedIn: true,
        isPremium: true,
        email: 'someone@example.com',
        userId: 'u1',
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('⭐ Premium'), findsOneWidget);
    expect(find.text('Cloud backup and sync'), findsOneWidget);
  });

  testWidgets('always offers a way back', (tester) async {
    await pump(
      tester,
      const AccountState(
        isConfigured: true,
        isSignedIn: false,
        isPremium: false,
      ),
    );
    expect(find.byType(AppBar), findsOneWidget);
  });

  // AdaptivePage returns its child untouched on compact widths, so the cases
  // above never exercise the constrained path the desktop app actually uses.
  testWidgets('renders on a desktop window', (tester) async {
    await pump(
      tester,
      const AccountState(
        isConfigured: true,
        isSignedIn: true,
        isPremium: false,
        email: 'someone@example.com',
        userId: 'u1',
      ),
      window: const Size(1280, 860),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Upgrade to Premium'), findsOneWidget);
  });

  testWidgets('renders signed out on a desktop window', (tester) async {
    await pump(
      tester,
      const AccountState(
        isConfigured: true,
        isSignedIn: false,
        isPremium: false,
      ),
      window: const Size(1280, 860),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('the form explains what is wrong instead of doing nothing',
      (tester) async {
    await pump(
      tester,
      const AccountState(isConfigured: true, isSignedIn: false, isPremium: false),
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Password must be at least 6 characters'), findsOneWidget);

    await tester.tap(find.text('Create account'));
    await tester.pump();
    expect(find.widgetWithText(FilledButton, 'Create free account'), findsOneWidget);
    expect(find.text('Forgot password?'), findsNothing);
  });

  test('auth errors are translated for people', () {
    expect(friendlyAuthError('Invalid login credentials'), 'Wrong email or password.');
    expect(friendlyAuthError('User already registered'), contains('Sign in instead'));
    expect(friendlyAuthError('Email not confirmed'), contains('check your inbox'));
    expect(friendlyAuthError('weird internal thing'), contains('try again'));
  });
}
