import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:roadmap_x/core/services/onboarding.dart';
import 'package:roadmap_x/core/services/shared_preferences_provider.dart';
import 'package:roadmap_x/features/walkthrough/tours.dart';
import 'package:roadmap_x/shared/widgets/walkthrough.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _steps = [
  WalkStep(title: 'Intro', body: 'Centred card'),
  WalkStep(target: 'a', title: 'Step A', body: 'Points at A'),
  WalkStep(target: 'missing', title: 'Never shown', body: '-'),
  WalkStep(target: 'b', title: 'Step B', body: 'Points at B'),
];

Future<SharedPreferences> _prefs({bool onboarded = true}) async {
  SharedPreferences.setMockInitialValues(
      {if (onboarded) Onboarding.completedKey: true});
  return SharedPreferences.getInstance();
}

Widget _app(SharedPreferences prefs,
        {List<WalkStep> steps = _steps, bool showTargets = true}) =>
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        home: WalkthroughTrigger(
          flow: 'demo',
          steps: steps,
          child: Scaffold(
            body: Column(
              children: [
                if (showTargets) ...[
                  const WalkTarget(id: 'a', child: Text('Target A')),
                  const SizedBox(height: 200),
                  const WalkTarget(id: 'b', child: Text('Target B')),
                ],
              ],
            ),
          ),
        ),
      ),
    );

/// The spotlight's ring pulses forever, so pumpAndSettle never would.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  setUp(() => Walkthrough.enabled = true);
  tearDown(() => Walkthrough.enabled = false);

  testWidgets('plays once, skips missing targets, marks the flow seen',
      (tester) async {
    final prefs = await _prefs();
    await tester.pumpWidget(_app(prefs));
    await _settle(tester);

    expect(find.text('Intro'), findsOneWidget);
    // The missing step is dropped from the count: 3 steps, not 4.
    expect(find.text('1/3'), findsOneWidget);
    expect(Walkthrough.hasSeen(prefs, 'demo'), isTrue);

    await tester.tap(find.text('Next'));
    await _settle(tester);
    expect(find.text('Step A'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await _settle(tester);
    expect(find.text('Never shown'), findsNothing);
    expect(find.text('Step B'), findsOneWidget);
    expect(find.text('3/3'), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await _settle(tester);
    expect(find.text('Step B'), findsNothing);

    // Rebuilding does not replay it.
    await tester.pumpWidget(_app(prefs));
    await _settle(tester);
    expect(find.text('Intro'), findsNothing);
  });

  testWidgets('Skip tour closes it', (tester) async {
    final prefs = await _prefs();
    await tester.pumpWidget(_app(prefs));
    await _settle(tester);
    await tester.tap(find.text('Skip tour'));
    await _settle(tester);
    expect(find.text('Intro'), findsNothing);
    expect(Walkthrough.isShowing, isFalse);
  });

  testWidgets('waits while onboarding is unfinished', (tester) async {
    final prefs = await _prefs(onboarded: false);
    await tester.pumpWidget(_app(prefs));
    await _settle(tester);
    expect(find.text('Intro'), findsNothing);
    expect(Walkthrough.hasSeen(prefs, 'demo'), isFalse);
  });

  testWidgets('a tour with nothing to point at is kept for later',
      (tester) async {
    final prefs = await _prefs();
    const targetedOnly = [
      WalkStep(target: 'a', title: 'Step A', body: '-'),
    ];
    await tester.pumpWidget(
        _app(prefs, steps: targetedOnly, showTargets: false));
    await _settle(tester);
    expect(find.text('Step A'), findsNothing);
    expect(Walkthrough.hasSeen(prefs, 'demo'), isFalse);

    // The target appears (e.g. a pet is adopted): the tour plays.
    await tester.pumpWidget(_app(prefs, steps: targetedOnly));
    await _settle(tester);
    expect(find.text('Step A'), findsOneWidget);
  });

  test('resetAll clears every flow', () async {
    final prefs = await _prefs();
    await Walkthrough.markSeen(prefs, Tours.today);
    await Walkthrough.markSeen(prefs, Tours.pet);
    await Walkthrough.resetAll(prefs);
    expect(Walkthrough.hasSeen(prefs, Tours.today), isFalse);
    expect(Walkthrough.hasSeen(prefs, Tours.pet), isFalse);
    expect(prefs.getBool(Onboarding.completedKey), isTrue);
  });
}
