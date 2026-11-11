import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:roadmap_x/shared/widgets/item_actions.dart';

/// The app-wide item rule: long-press and ⋯ open the same options sheet,
/// destructive actions always come last, swipe left reveals Edit and Delete.
void main() {
  late List<String> fired;

  List<ItemAction> actions() => [
        // Listed out of order on purpose: Delete must still render last.
        ItemAction(
          label: 'Delete',
          icon: Icons.delete_outline,
          destructive: true,
          onSelected: () => fired.add('delete'),
        ),
        ItemAction(
          label: 'Edit',
          icon: Icons.edit_outlined,
          onSelected: () => fired.add('edit'),
        ),
        ItemAction(
          label: 'Archive',
          icon: Icons.archive_outlined,
          onSelected: () => fired.add('archive'),
        ),
      ];

  Future<void> pump(WidgetTester tester) async {
    fired = [];
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ItemSwipeActions(
            itemKey: const ValueKey('row'),
            onEdit: () => fired.add('swipe-edit'),
            onDelete: () => fired.add('swipe-delete'),
            child: ListTile(
              title: const Text('Row'),
              onLongPress: () => showItemActions(context,
                  title: 'Row', actions: actions()),
              trailing: ItemActionsButton(title: 'Row', actions: actions),
            ),
          ),
        ),
      ),
    ));
  }

  List<String> sheetLabels(WidgetTester tester) => [
        for (final t in tester.widgetList<ListTile>(find.descendant(
            of: find.byType(BottomSheet), matching: find.byType(ListTile))))
          ((t.title as Text).data ?? ''),
      ];

  testWidgets('long-press and ⋯ open the same sheet, Delete last',
      (tester) async {
    await pump(tester);

    await tester.longPress(find.text('Row'));
    await tester.pumpAndSettle();
    final fromLongPress = sheetLabels(tester);
    expect(fromLongPress, ['Edit', 'Archive', 'Delete']);
    await tester.tapAt(const Offset(10, 10)); // dismiss
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Options'));
    await tester.pumpAndSettle();
    expect(sheetLabels(tester), fromLongPress,
        reason: 'the ⋯ button shows exactly what long-press shows');

    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(fired, ['archive']);
  });

  testWidgets('swipe left reveals Edit then Delete', (tester) async {
    await pump(tester);
    await tester.drag(find.text('Row'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    final edit = tester.getTopLeft(find.text('Edit'));
    final delete = tester.getTopLeft(find.text('Delete'));
    expect(edit.dx, lessThan(delete.dx));

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(fired, ['swipe-delete']);
  });
}
