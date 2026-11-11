import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../core/layout/adaptive_sheet.dart';

/// One action an item offers: "Edit", "Archive", "Delete", …
class ItemAction {
  const ItemAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;

  /// Drawn in red and always placed last.
  final bool destructive;
}

/// The single interaction rule for every list item in the app:
///
/// - **Tap** opens the item (a habit is ticked instead; that is its job).
/// - **Long-press** opens the options sheet. List items carry no ⋯ button;
///   [ItemActionsButton] is only for page-level menus such as a top bar.
/// - **Swipe left** reveals Edit and Delete.
/// - **Drag handle** reorders, where order matters.
///
/// Every screen goes through these helpers, so the same gesture always does
/// the same thing wherever it is used.
Future<void> showItemActions(
  BuildContext context, {
  required String title,
  required List<ItemAction> actions,
}) async {
  HapticFeedback.selectionClick();
  // Destructive actions last, whatever order the caller listed them in.
  final ordered = [
    ...actions.where((a) => !a.destructive),
    ...actions.where((a) => a.destructive),
  ];
  final chosen = await showAdaptiveSheet<ItemAction>(
    context: context,
    builder: (sheetContext) {
      final cs = Theme.of(sheetContext).colorScheme;
      final tt = Theme.of(sheetContext).textTheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              for (final action in ordered) ...[
                if (action.destructive &&
                    action == ordered.firstWhere((a) => a.destructive))
                  Divider(height: 8, color: cs.outline),
                ListTile(
                  leading: Icon(
                    action.icon,
                    color: action.destructive ? cs.error : cs.onSurfaceVariant,
                  ),
                  title: Text(
                    action.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: action.destructive ? cs.error : null,
                    ),
                  ),
                  onTap: () => Navigator.pop(sheetContext, action),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
  chosen?.onSelected();
}

/// The ⋯ button, for page-level menus only (e.g. the goal page's top bar).
/// List items use long-press instead. Opens the same sheet as long-press.
class ItemActionsButton extends StatelessWidget {
  const ItemActionsButton({
    super.key,
    required this.title,
    required this.actions,
    this.size = 20,
  });

  final String title;
  final List<ItemAction> Function() actions;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: 'Options',
      visualDensity: VisualDensity.compact,
      icon:
          Icon(Icons.more_vert_rounded, size: size, color: cs.onSurfaceVariant),
      onPressed: () =>
          showItemActions(context, title: title, actions: actions()),
    );
  }
}

/// Swipe left for Edit and Delete. The same two actions, colours and order
/// on every item that can be edited.
class ItemSwipeActions extends StatelessWidget {
  const ItemSwipeActions({
    super.key,
    required this.itemKey,
    required this.onEdit,
    required this.onDelete,
    required this.child,
    this.radius = 14,
  });

  final Key itemKey;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Slidable(
      key: itemKey,
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.5,
        children: [
          SlidableAction(
            onPressed: (_) => onEdit(),
            backgroundColor: cs.primary,
            foregroundColor: Colors.white,
            icon: Icons.edit_outlined,
            label: 'Edit',
            borderRadius:
                BorderRadius.horizontal(left: Radius.circular(radius)),
          ),
          SlidableAction(
            onPressed: (_) => onDelete(),
            backgroundColor: cs.error,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline,
            label: 'Delete',
            borderRadius:
                BorderRadius.horizontal(right: Radius.circular(radius)),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// The drag handle for reorderable lists. Long-press is reserved for the
/// options sheet, so reordering always starts from this handle.
class ItemDragHandle extends StatelessWidget {
  const ItemDragHandle({super.key, required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ReorderableDragStartListener(
      index: index,
      child: Tooltip(
        message: 'Drag to reorder',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Icon(
            Icons.drag_indicator_rounded,
            size: 20,
            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}
