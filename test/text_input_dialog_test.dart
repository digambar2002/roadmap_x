import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:roadmap_x/shared/widgets/text_input_dialog.dart';

/// Regression: renaming the pet showed a red error screen on Cancel and froze
/// on Save, because the text controller was disposed mid-animation.
void main() {
  Future<String?> open(WidgetTester tester, Future<void> Function() act) async {
    String? result = 'untouched';
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showTextInputDialog(
              context,
              title: 'Rename your pet',
              initialValue: 'Mochi',
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await act();
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('Cancel closes cleanly and returns null', (tester) async {
    final result = await open(tester, () => tester.tap(find.text('Cancel')));
    expect(tester.takeException(), isNull);
    expect(result, isNull);
    expect(find.text('Rename your pet'), findsNothing);
  });

  testWidgets('Save returns the trimmed text and closes', (tester) async {
    final result = await open(tester, () async {
      await tester.enterText(find.byType(TextField), '  Biscuit  ');
      await tester.tap(find.text('Save'));
    });
    expect(tester.takeException(), isNull);
    expect(result, 'Biscuit');
    expect(find.text('Rename your pet'), findsNothing);
  });

  testWidgets('Enter on the keyboard saves too', (tester) async {
    final result = await open(tester, () async {
      await tester.enterText(find.byType(TextField), 'Rex');
      await tester.testTextInput.receiveAction(TextInputAction.done);
    });
    expect(result, 'Rex');
  });
}
