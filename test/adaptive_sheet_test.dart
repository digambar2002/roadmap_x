import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:roadmap_x/core/layout/adaptive_sheet.dart';
import 'package:roadmap_x/core/theme/app_theme.dart';

/// Sheets built for a bottom-sheet host do not automatically survive being
/// re-presented as a dialog. DraggableScrollableSheet in particular sizes
/// itself as a fraction of its parent and assumes that parent is the screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> open(
    WidgetTester tester,
    Size window,
    WidgetBuilder builder, {
    Color? background,
  }) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showAdaptiveSheet<void>(
                    context: context,
                    backgroundColor: background,
                    builder: builder,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Widget draggableContent(BuildContext context) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => ColoredBox(
          color: Colors.blue,
          child: ListView(
            controller: controller,
            children: const [
              SizedBox(height: 80, child: Text('sheet content')),
            ],
          ),
        ),
      );

  testWidgets('a draggable sheet fills the screen on a phone', (tester) async {
    await open(tester, const Size(430, 932), draggableContent,
        background: Colors.transparent);
    expect(tester.takeException(), isNull);

    final height = tester.getSize(find.byType(DraggableScrollableSheet)).height;
    expect(height, greaterThan(200));
    expect(find.text('sheet content'), findsOneWidget);
  });

  testWidgets('a draggable sheet is visible as a dialog too', (tester) async {
    await open(tester, const Size(1280, 860), draggableContent,
        background: Colors.transparent);
    expect(tester.takeException(), isNull);

    final size = tester.getSize(find.byType(DraggableScrollableSheet));
    expect(size.height, greaterThan(200),
        reason: 'a collapsed sheet reads to the user as a blank screen');
    expect(find.text('sheet content'), findsOneWidget);
  });

  testWidgets('a plain column sheet is visible as a dialog', (tester) async {
    await open(
      tester,
      const Size(1280, 860),
      (_) => const Column(
        mainAxisSize: MainAxisSize.min,
        children: [SizedBox(height: 120, child: Text('plain content'))],
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('plain content'), findsOneWidget);
  });

  testWidgets('closing with the opener\'s context dismisses the sheet, '
      'not the page', (tester) async {
    // Every call site closes its sheet with Navigator.pop(screenContext).
    // If the dialog lives on a different navigator than the bottom sheet did,
    // that pop removes the page instead and the app goes blank.
    for (final window in const [Size(430, 932), Size(1280, 860)]) {
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => showAdaptiveSheet<void>(
                      context: context,
                      builder: (_) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            // Deliberately the opener's context, not the
                            // sheet's — this is what the real screens do.
                            onPressed: () => Navigator.pop(context),
                            child: const Text('close'),
                          ),
                        ],
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('close'), findsOneWidget);

      await tester.tap(find.text('close'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'at ${window.width}px');
      expect(find.text('close'), findsNothing, reason: 'sheet closed');
      expect(find.text('open'), findsOneWidget,
          reason: 'the page survives at ${window.width}px');
    }
  });
}
