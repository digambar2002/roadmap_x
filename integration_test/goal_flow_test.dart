import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:roadmap_x/main.dart' as app;

/// Drives the real app on the real platform.
///
/// Widget tests kept passing while users reported blank screens, because they
/// pump one widget with stub providers. This runs main(), the real router, the
/// real database and the real window size — which is where the difference has
/// been hiding.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> boot(WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));
  }

  void report(String label) => debugPrint('### $label');

  testWidgets('Goals -> New Goal -> Generate with AI', (tester) async {
    await boot(tester);
    report('booted; window=${tester.view.physicalSize}');

    // Navigate to Goals.
    final goalsTab = find.text('Goals');
    expect(goalsTab, findsWidgets, reason: 'nav item should exist');
    await tester.tap(goalsTab.first);
    await tester.pumpAndSettle();
    report('on goals screen');

    // Open the creation options.
    final fab = find.text('New Goal');
    expect(fab, findsOneWidget);
    await tester.tap(fab);
    await tester.pumpAndSettle();
    report('options open: ${find.text('✦ Generate with AI').evaluate().length} ai entries');

    expect(find.text('✦ Generate with AI'), findsOneWidget,
        reason: 'the options sheet itself must render');

    await tester.tap(find.text('✦ Generate with AI'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Whatever appears — the AI sheet or the premium upsell — it has to be
    // something the user can read and dismiss, not an empty surface.
    final sawAiSheet = find.text('Describe your goal').evaluate().isNotEmpty ||
        find.textContaining('AI').evaluate().isNotEmpty;
    final sawUpsell =
        find.text('AI coach is a premium feature').evaluate().isNotEmpty;
    report('after tap: aiSheet=$sawAiSheet upsell=$sawUpsell');
    report('visible texts: '
        '${find.byType(Text).evaluate().take(25).map((e) => (e.widget as Text).data).where((t) => t != null && t.isNotEmpty).toList()}');

    expect(tester.takeException(), isNull);
    expect(sawAiSheet || sawUpsell, isTrue,
        reason: 'tapping Generate with AI must show something');
  });
}
