import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:roadmap_x/core/ai/ai_access.dart';
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
    AiAccess access = AiAccess.free,
    int? plansLeft = 0,
    ValueChanged<bool>? onResult,
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
                  onPressed: () async {
                    final ok = await action(context, ref);
                    onResult?.call(ok);
                  },
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
          aiAccessProvider.overrideWithValue(access),
          // Nothing here watches the account stream before the tap, so
          // state it outright rather than racing its first event.
          syncAvailableProvider.overrideWithValue(true),
          freeAiPlansLeftProvider.overrideWith((ref) async => plansLeft),
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
      expect(find.text('This month\'s free AI plans are used'), findsOneWidget);
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
      expect(find.text('This month\'s free AI plans are used'), findsNothing);
      expect(find.text('locked feature'), findsOneWidget);
    });
  }

  const phone = Size(430, 932);

  testWidgets('a free account with plans left goes straight through',
      (tester) async {
    bool? result;
    await pumpGate(tester,
        window: phone,
        action: PremiumGate.ensureAi,
        plansLeft: 2,
        onResult: (r) => result = r);
    expect(result, isTrue);
    expect(find.text('Not now'), findsNothing);
  });

  testWidgets('an unknown count lets the server decide', (tester) async {
    bool? result;
    await pumpGate(tester,
        window: phone,
        action: PremiumGate.ensureAi,
        plansLeft: null,
        onResult: (r) => result = r);
    expect(result, isTrue);
  });

  testWidgets('own key and Premium are never gated', (tester) async {
    for (final access in [AiAccess.ownKey, AiAccess.premium]) {
      bool? result;
      await pumpGate(tester,
          window: phone,
          action: PremiumGate.ensureAi,
          access: access,
          onResult: (r) => result = r);
      expect(result, isTrue, reason: '$access');
    }
  });

  testWidgets('signed out is offered a free sign-in, not a paywall',
      (tester) async {
    await pumpGate(tester,
        window: phone, action: PremiumGate.ensureAi, access: AiAccess.none);
    expect(find.text('Let AI build your plan, free'), findsOneWidget);
    await tester.tap(find.text('Sign in free'));
    await tester.pumpAndSettle();
    expect(find.text('premium page'), findsOneWidget);
  });
}
