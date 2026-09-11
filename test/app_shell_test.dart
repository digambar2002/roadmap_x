import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:roadmap_x/core/router/app_shell.dart';

/// Navigation moves from the bottom edge to the side as the window grows.
/// Getting this wrong is the single most visible way the app reads as a phone
/// port on a desktop.
void main() {
  GoRouter buildRouter() => GoRouter(
        initialLocation: '/a',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, shell) => AppShell(navigationShell: shell),
            branches: [
              for (final path in ['/a', '/b', '/c', '/d', '/e'])
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: path,
                      builder: (_, __) => Scaffold(body: Text('page $path')),
                    ),
                  ],
                ),
            ],
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const Scaffold(body: Text('settings')),
          ),
        ],
      );

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('phone width keeps navigation at the bottom', (tester) async {
    await pumpAt(tester, const Size(400, 900));
    expect(tester.takeException(), isNull);

    final nav = tester.getTopLeft(find.text('Home'));
    final page = tester.getTopLeft(find.text('page /a'));
    expect(nav.dy, greaterThan(page.dy), reason: 'labels sit below the page');
  });

  testWidgets('tablet width moves navigation to the side', (tester) async {
    await pumpAt(tester, const Size(900, 800));
    expect(tester.takeException(), isNull);

    // Icon-only rail: labels are tooltips, so the visible text is gone.
    expect(find.text('Home'), findsNothing);
    final page = tester.getTopLeft(find.text('page /a'));
    expect(page.dx, greaterThan(0), reason: 'page is inset by the rail');
  });

  testWidgets('desktop width labels the side rail', (tester) async {
    await pumpAt(tester, const Size(1400, 900));
    expect(tester.takeException(), isNull);

    expect(find.text('RoadmapX'), findsOneWidget, reason: 'rail header');
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    final home = tester.getTopLeft(find.text('Home'));
    final page = tester.getTopLeft(find.text('page /a'));
    expect(home.dx, lessThan(page.dx), reason: 'rail is left of the page');
  });

  testWidgets('side rail switches branches', (tester) async {
    await pumpAt(tester, const Size(1400, 900));

    await tester.tap(find.text('Goals'));
    await tester.pumpAndSettle();

    expect(find.text('page /c'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives a resize across the breakpoint', (tester) async {
    await pumpAt(tester, const Size(400, 900));
    expect(find.text('page /a'), findsOneWidget);

    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('RoadmapX'), findsOneWidget);
    expect(find.text('page /a'), findsOneWidget);
  });
}
