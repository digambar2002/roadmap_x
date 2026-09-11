import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmap_x/core/theme/app_theme.dart';

/// flutter_test pins defaultTargetPlatform to android, so the desktop branch of
/// the theme is never exercised unless it is overridden explicitly. It went
/// unbuilt once and shipped an assertion that blanked the entire app.
void main() {
  // google_fonts reaches for ServicesBinding while building the text theme.
  TestWidgetsFlutterBinding.ensureInitialized();

  /// flutter_test asserts that foundation debug variables are restored before
  /// tearDown runs, so the override has to be undone inside the test body.
  Future<T> withPlatform<T>(
    TargetPlatform platform,
    Future<T> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      return await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  /// Reads the theme from inside MaterialApp, where Typography has merged the
  /// geometry in and font sizes actually exist.
  Future<TextTheme> resolvedTextTheme(WidgetTester tester) async {
    late TextTheme result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        builder: (context, child) => Theme(
          data: AppTheme.densifyForPointer(Theme.of(context)),
          child: child ?? const SizedBox.shrink(),
        ),
        home: Builder(
          builder: (c) {
            result = Theme.of(c).textTheme;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return result;
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    testWidgets('$platform builds and keeps every size resolved',
        (tester) async {
      final t = await withPlatform(platform, () => resolvedTextTheme(tester));

      expect(tester.takeException(), isNull);
      for (final style in [
        t.displayLarge, t.displayMedium, t.displaySmall,
        t.headlineLarge, t.headlineMedium, t.headlineSmall,
        t.titleLarge, t.titleMedium, t.titleSmall,
        t.bodyLarge, t.bodyMedium, t.bodySmall,
        t.labelLarge, t.labelMedium, t.labelSmall,
      ]) {
        expect(style?.fontSize, isNotNull);
      }
    });

    testWidgets('$platform type is smaller than on touch', (tester) async {
      final touch = (await withPlatform(
        TargetPlatform.android,
        () => resolvedTextTheme(tester),
      ))
          .bodyMedium!
          .fontSize!;

      final desktop = (await withPlatform(
        platform,
        () => resolvedTextTheme(tester),
      ))
          .bodyMedium!
          .fontSize!;

      expect(desktop, lessThan(touch));
      // A trim, not a redesign: the hierarchy has to survive.
      expect(desktop, greaterThan(touch * 0.85));
    });
  }

  testWidgets('touch platforms keep Material defaults', (tester) async {
    final t = await withPlatform(
      TargetPlatform.android,
      () => resolvedTextTheme(tester),
    );
    expect(t.bodyMedium!.fontSize, 14.0);
    expect(t.titleLarge!.fontSize, 22.0);
  });

  testWidgets('desktop keeps the type hierarchy intact', (tester) async {
    final t = await withPlatform(
      TargetPlatform.macOS,
      () => resolvedTextTheme(tester),
    );
    expect(t.headlineSmall!.fontSize, greaterThan(t.titleLarge!.fontSize!));
    expect(t.titleLarge!.fontSize, greaterThan(t.bodyMedium!.fontSize!));
    expect(t.bodyMedium!.fontSize, greaterThan(t.labelSmall!.fontSize!));
  });
}
