import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:roadmap_x/core/sync/account_service.dart';
import 'package:roadmap_x/core/theme/app_theme.dart';
import 'package:roadmap_x/features/premium/presentation/premium_gate.dart';
import 'package:roadmap_x/features/premium/providers/premium_provider.dart';

/// The upsell is what a locked feature shows instead of doing nothing. On a
/// desktop window it is presented as a dialog rather than a bottom sheet, and
/// that path is not reachable from a phone-sized test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpGate(
    WidgetTester tester, {
    required Size window,
    required Future<bool> Function(BuildContext, WidgetRef) action,
  }) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Consumer(
            builder: (context, ref, __) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => action(context, ref),
                  child: const Text('locked feature'),
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/premium',
          builder: (_, __) => const Scaffold(body: Text('premium page')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith(
            (ref) => Stream.value(
              const AccountState(
                isConfigured: true,
                isSignedIn: true,
                isPremium: false,
                email: 'someone@example.com',
                userId: 'u1',
              ),
            ),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.dark,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('locked feature'));
    await tester.pumpAndSettle();
  }

  for (final window in const [Size(430, 932), Size(1280, 860)]) {
    final kind = window.width < 640 ? 'sheet' : 'dialog';

    testWidgets('AI gate shows the locked message as a $kind', (tester) async {
      await pumpGate(
        tester,
        window: window,
        action: PremiumGate.ensureAi,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('AI coach is a premium feature'), findsOneWidget);
      expect(find.textContaining('RoadmapX Premium'), findsWidgets);
      // Both a way forward and a way out.
      expect(find.text('Not now'), findsOneWidget);
    });

    testWidgets('the $kind routes to the premium page', (tester) async {
      await pumpGate(
        tester,
        window: window,
        action: PremiumGate.ensureAi,
      );

      await tester.tap(find.textContaining('See RoadmapX Premium'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('premium page'), findsOneWidget);
    });

    testWidgets('the $kind can be dismissed', (tester) async {
      await pumpGate(
        tester,
        window: window,
        action: PremiumGate.ensureAi,
      );

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('AI coach is a premium feature'), findsNothing);
      expect(find.text('locked feature'), findsOneWidget);
    });
  }
}
