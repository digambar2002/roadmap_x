import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// How much room the window has, independent of which OS it is.
///
/// Width rather than platform decides *layout* — a half-width window on a Mac
/// should behave like a phone, and a tablet in landscape should not. Platform
/// decides *density* separately (see [isPointerPlatform]): that follows the
/// input device, not the window.
enum WindowSize {
  /// Phones, and any narrow window. One column, bottom navigation.
  compact,

  /// Small tablets and half-screen desktop windows. One column, side rail.
  medium,

  /// Full-screen desktop. Multiple columns, labelled side rail.
  expanded,
}

class Breakpoints {
  const Breakpoints._();

  static const double medium = 640;
  static const double expanded = 1080;

  /// Comfortable measure for a single column of text and list rows.
  ///
  /// Rows stretched across a 2000px monitor are the main reason the app read
  /// as a blown-up phone: the eye has to travel the full width to pair a label
  /// on the left with its value on the right.
  static const double readableMaxWidth = 780;

  /// Ceiling for screens that lay out several columns side by side.
  static const double wideMaxWidth = 1240;

  static WindowSize sizeFor(double width) {
    if (width >= expanded) return WindowSize.expanded;
    if (width >= medium) return WindowSize.medium;
    return WindowSize.compact;
  }
}

extension WindowSizeX on BuildContext {
  WindowSize get windowSize =>
      Breakpoints.sizeFor(MediaQuery.sizeOf(this).width);

  bool get isCompact => windowSize == WindowSize.compact;
  bool get isExpanded => windowSize == WindowSize.expanded;

  /// Navigation moves to the side as soon as there is room, which frees the
  /// bottom edge and matches where desktop users look for it.
  bool get usesSideNav => windowSize != WindowSize.compact;

  /// Side padding for a page's content.
  double get pageGutter => switch (windowSize) {
        WindowSize.compact => 20,
        WindowSize.medium => 24,
        WindowSize.expanded => 32,
      };

  /// Vertical rhythm between major sections. Desktop can afford less, because
  /// more fits on screen and large gaps read as emptiness rather than grouping.
  double get sectionGap => switch (windowSize) {
        WindowSize.compact => 24,
        WindowSize.medium => 20,
        WindowSize.expanded => 20,
      };
}

/// True where the primary input is a mouse or trackpad.
///
/// Drives control density, which is a property of the pointer rather than the
/// window: a 44pt touch target is right for a fingertip and wastefully large
/// for a cursor, whatever size the window happens to be.
bool get isPointerPlatform =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux;
