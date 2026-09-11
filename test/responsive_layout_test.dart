import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmap_x/core/layout/adaptive_page.dart';
import 'package:roadmap_x/core/layout/breakpoints.dart';

void main() {
  group('breakpoints', () {
    test('classify by width, not by platform', () {
      expect(Breakpoints.sizeFor(390), WindowSize.compact);
      expect(Breakpoints.sizeFor(639), WindowSize.compact);
      expect(Breakpoints.sizeFor(640), WindowSize.medium);
      expect(Breakpoints.sizeFor(1079), WindowSize.medium);
      expect(Breakpoints.sizeFor(1080), WindowSize.expanded);
      expect(Breakpoints.sizeFor(2560), WindowSize.expanded);
    });

    test('side navigation starts at medium', () {
      expect(Breakpoints.sizeFor(500) != WindowSize.compact, isFalse);
      expect(Breakpoints.sizeFor(800) != WindowSize.compact, isTrue);
    });
  });

  group('AdaptivePage', () {
    Future<double> contentWidth(WidgetTester tester, double windowWidth) async {
      tester.view.physicalSize = Size(windowWidth, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptivePage(
              child: SizedBox.expand(child: ColoredBox(color: Colors.red)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getSize(find.byType(SizedBox).first).width;
    }

    testWidgets('leaves a phone-width window alone', (tester) async {
      expect(await contentWidth(tester, 400), 400);
    });

    testWidgets('caps the measure on a wide window', (tester) async {
      // Without this, list rows stretch the full width of a monitor and the
      // eye has to travel to pair a label with its value.
      expect(await contentWidth(tester, 2000), Breakpoints.readableMaxWidth);
    });

    testWidgets('centres the capped content', (tester) async {
      tester.view.physicalSize = const Size(2000, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdaptivePage(
              child: SizedBox.expand(child: ColoredBox(color: Colors.red)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final left = tester.getTopLeft(find.byType(SizedBox).first).dx;
      final expected = (2000 - Breakpoints.readableMaxWidth) / 2;
      expect(left, closeTo(expected, 1));
    });
  });

  group('AdaptiveColumns', () {
    Future<void> pump(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveColumns(
              main: Container(key: const Key('main'), height: 100),
              side: Container(key: const Key('side'), height: 100),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('stacks on a narrow window', (tester) async {
      await pump(tester, 500);
      final main = tester.getTopLeft(find.byKey(const Key('main')));
      final side = tester.getTopLeft(find.byKey(const Key('side')));
      expect(side.dy, greaterThan(main.dy), reason: 'side sits below main');
      expect(side.dx, main.dx);
    });

    testWidgets('sits side by side on a wide window', (tester) async {
      await pump(tester, 1400);
      final main = tester.getTopLeft(find.byKey(const Key('main')));
      final side = tester.getTopLeft(find.byKey(const Key('side')));
      expect(side.dx, greaterThan(main.dx), reason: 'side is to the right');
      expect(side.dy, main.dy, reason: 'both start at the same height');
    });
  });
}
