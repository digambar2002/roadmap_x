import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmap_x/features/dashboard/presentation/widgets/stat_strip.dart';

/// Four tiles share one row, so the narrow end is where this breaks.
///
/// These pump the strip inside a CustomScrollView sliver, which is where the
/// dashboard actually uses it. An earlier version of this file wrapped it in a
/// plain Scaffold body instead — that supplies a bounded height, so it happily
/// passed while the real screen was throwing "BoxConstraints forces an
/// infinite height" and rendering nothing at all.
void main() {
  final stats = [
    const DashboardStat(
      value: '12',
      label: 'Overdue',
      icon: Icons.error_outline_rounded,
      color: Colors.red,
    ),
    const DashboardStat(
      value: '8',
      label: 'Today',
      icon: Icons.today_rounded,
      color: Colors.blue,
    ),
    const DashboardStat(
      value: '100%',
      label: 'Progress',
      icon: Icons.trending_up_rounded,
      color: Colors.green,
    ),
    const DashboardStat(
      value: '365',
      label: 'Streak',
      icon: Icons.local_fire_department_rounded,
      color: Colors.orange,
    ),
  ];

  Future<void> pumpAt(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: StatStrip(stats: stats),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lays out without overflow on a small phone', (tester) async {
    await pumpAt(tester, 320);
    expect(tester.takeException(), isNull);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('365'), findsOneWidget);
  });

  testWidgets('lays out without overflow on a typical phone', (tester) async {
    await pumpAt(tester, 400);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lays out without overflow on a wide desktop window',
      (tester) async {
    await pumpAt(tester, 1400);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tiles end up the same height', (tester) async {
    await pumpAt(tester, 400);
    expect(tester.takeException(), isNull);

    final heights = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(StatStrip),
            matching: find.byType(Container),
          ),
        )
        .map((c) => tester.getSize(find.byWidget(c)).height)
        .toSet();
    expect(heights.length, 1, reason: 'all four tiles share one height');
  });
}
