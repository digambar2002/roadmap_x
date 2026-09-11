import 'package:flutter/material.dart';

import 'breakpoints.dart';

/// Marks the surface a sheet's content is currently being shown on.
///
/// Lets shared widgets adapt without every sheet having to thread a flag down
/// by hand — see [BottomSheetHandle], which is meaningless in a dialog because
/// there is nothing to drag.
class AdaptiveSheetScope extends InheritedWidget {
  const AdaptiveSheetScope({
    super.key,
    required this.isDialog,
    required super.child,
  });

  final bool isDialog;

  static bool isDialogOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AdaptiveSheetScope>()
          ?.isDialog ??
      false;

  @override
  bool updateShouldNotify(AdaptiveSheetScope oldWidget) =>
      isDialog != oldWidget.isDialog;
}

/// Presents [builder] as a bottom sheet on narrow windows and a centred dialog
/// on wide ones.
///
/// A sheet sliding up from the bottom edge of a 27-inch monitor is one of the
/// strongest "this is a phone app" signals there is: the content lands far from
/// where the cursor is and the travel is enormous. The same content in a
/// centred dialog reads as native without any of it being rewritten.
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  Color? backgroundColor,
  ShapeBorder? shape,
  double dialogMaxWidth = 560,
}) {
  if (!context.usesSideNav) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: backgroundColor ?? Colors.transparent,
      shape: shape,
      builder: (ctx) => AdaptiveSheetScope(isDialog: false, child: builder(ctx)),
    );
  }

  final cs = Theme.of(context).colorScheme;
  return showDialog<T>(
    context: context,
    barrierDismissible: true,
    // Must match showModalBottomSheet, which defaults to false. showDialog
    // defaults to true, which would put the dialog on the root navigator
    // while call sites still close it with `Navigator.pop(screenContext)` —
    // and that pops the GoRouter *page* instead, emptying the stack and
    // blanking the app.
    useRootNavigator: false,
    builder: (ctx) => Dialog(
      backgroundColor: backgroundColor == Colors.transparent
          ? Colors.transparent
          : backgroundColor ?? cs.surface,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: cs.outline),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogMaxWidth,
          // Dialogs do not get the sheet's drag-to-resize, so cap the height
          // and let the content scroll inside instead of overflowing.
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.86,
        ),
        child: AdaptiveSheetScope(isDialog: true, child: builder(ctx)),
      ),
    ),
  );
}
