import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/onboarding.dart';
import '../../core/services/shared_preferences_provider.dart';

/// One stop on a guided tour.
///
/// [target] names a [WalkTarget] on screen. A step whose target isn't
/// showing (an empty list, a card that only appears on some days) is
/// skipped. A step with no target is shown as a centred card.
class WalkStep {
  const WalkStep({
    this.target,
    required this.title,
    required this.body,
    this.emoji,
  });

  final String? target;
  final String title;
  final String body;
  final String? emoji;
}

/// Marks a widget a tour can point at. Ids are unique per flow
/// ("today.fab", "goals.card"); if two are mounted, the latest wins.
class WalkTarget extends StatefulWidget {
  const WalkTarget({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  State<WalkTarget> createState() => _WalkTargetState();
}

class _WalkTargetState extends State<WalkTarget> {
  @override
  void initState() {
    super.initState();
    Walkthrough._targets[widget.id] = this;
  }

  @override
  void didUpdateWidget(WalkTarget old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      if (Walkthrough._targets[old.id] == this) {
        Walkthrough._targets.remove(old.id);
      }
      Walkthrough._targets[widget.id] = this;
    }
  }

  @override
  void dispose() {
    if (Walkthrough._targets[widget.id] == this) {
      Walkthrough._targets.remove(widget.id);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Guided tours: a spotlight on each part of a screen with a short note,
/// shown once per flow the first time the user opens it.
class Walkthrough {
  const Walkthrough._();

  static final Map<String, _WalkTargetState> _targets = {};

  /// Off under `flutter test`, so widget tests aren't covered by a tour.
  /// Tests of the tour itself switch it back on.
  static bool enabled =
      kIsWeb || !Platform.environment.containsKey('FLUTTER_TEST');

  static bool _showing = false;
  static bool get isShowing => _showing;

  /// Bumped by "Replay app tour" so screens already open re-check.
  static final ValueNotifier<int> replayTick = ValueNotifier(0);

  static const _prefix = 'walkthrough_seen_';
  static String seenKey(String flow) => '$_prefix$flow';

  static bool hasSeen(SharedPreferences prefs, String flow) =>
      prefs.getBool(seenKey(flow)) ?? false;

  static Future<void> markSeen(SharedPreferences prefs, String flow) =>
      prefs.setBool(seenKey(flow), true);

  /// Clears every flow's flag so each tour shows again.
  static Future<void> resetAll(SharedPreferences prefs) async {
    for (final k in prefs.getKeys().where((k) => k.startsWith(_prefix))) {
      await prefs.remove(k);
    }
    replayTick.value++;
  }

  /// Plays [steps] now. Completes when the tour is finished or skipped.
  static Future<void> show(BuildContext context, List<WalkStep> steps) async {
    if (_showing || steps.isEmpty) return;
    _showing = true;
    try {
      await showGeneralDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        barrierColor: Colors.transparent,
        barrierLabel: 'App tour',
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, __, ___) => _WalkOverlay(steps: steps),
        transitionBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      );
    } finally {
      _showing = false;
    }
  }

  static _WalkTargetState? _find(String id) {
    final s = _targets[id];
    if (s == null || !s.mounted) return null;
    final box = s.context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    if (box.size.isEmpty) return null;
    return s;
  }

  /// Whether at least one of [steps] can be shown right now.
  static bool _anyShowable(List<WalkStep> steps) =>
      steps.any((s) => s.target == null || _find(s.target!) != null);
}

/// Wraps a screen and plays its tour the first time the screen is the one
/// in front: not hidden in another tab, not under a sheet or dialog.
class WalkthroughTrigger extends ConsumerStatefulWidget {
  const WalkthroughTrigger({
    super.key,
    required this.flow,
    required this.steps,
    required this.child,
    this.delay = const Duration(milliseconds: 700),
  });

  final String flow;
  final List<WalkStep> steps;
  final Widget child;

  /// Lets the screen's data load first, so lists have rows to point at.
  final Duration delay;

  @override
  ConsumerState<WalkthroughTrigger> createState() => _WalkthroughTriggerState();
}

class _WalkthroughTriggerState extends ConsumerState<WalkthroughTrigger> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    Walkthrough.replayTick.addListener(_schedule);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // TickerMode turns on when this tab becomes the visible one, which
    // re-runs this, so each tab's tour waits until the tab is opened.
    if (TickerMode.valuesOf(context).enabled) _schedule();
  }

  @override
  void didUpdateWidget(WalkthroughTrigger old) {
    super.didUpdateWidget(old);
    // The screen rebuilt, perhaps with the content a tour needs (a pet was
    // adopted, the first goal created). Re-check while the tour is unseen.
    if (!Walkthrough.enabled) return;
    final prefs = ref.read(sharedPreferencesProvider);
    if (!Walkthrough.hasSeen(prefs, widget.flow)) _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    Walkthrough.replayTick.removeListener(_schedule);
    super.dispose();
  }

  void _schedule() {
    if (!Walkthrough.enabled) return;
    _timer?.cancel();
    _timer = Timer(widget.delay, _maybeShow);
  }

  bool _inFront() {
    if (!TickerMode.valuesOf(context).enabled) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    final root = Navigator.maybeOf(context, rootNavigator: true);
    // Inside a tab's own navigator: anything pushed on the root navigator
    // (a sheet, a dialog, a full-screen page) is covering this screen.
    if (root != null && route?.navigator != root && root.canPop()) {
      return false;
    }
    return true;
  }

  Future<void> _maybeShow() async {
    if (!mounted || Walkthrough.isShowing) return;
    final prefs = ref.read(sharedPreferencesProvider);
    if (!Onboarding.isComplete(prefs)) return;
    if (Walkthrough.hasSeen(prefs, widget.flow)) return;
    if (!_inFront()) return;
    // Nothing to point at yet (no pet adopted): wait for a later visit
    // rather than using the tour up on an empty screen.
    if (!Walkthrough._anyShowable(widget.steps)) return;
    await Walkthrough.markSeen(prefs, widget.flow);
    if (!mounted) return;
    await Walkthrough.show(context, widget.steps);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ── Overlay ───────────────────────────────────────────────

class _WalkOverlay extends StatefulWidget {
  const _WalkOverlay({required this.steps});
  final List<WalkStep> steps;

  @override
  State<_WalkOverlay> createState() => _WalkOverlayState();
}

class _WalkOverlayState extends State<_WalkOverlay>
    with SingleTickerProviderStateMixin {
  /// Steps whose target exists (or that have none), fixed at the start so
  /// the "2 of 5" count stays honest.
  late final List<WalkStep> _steps = [
    for (final s in widget.steps)
      if (s.target == null || Walkthrough._find(s.target!) != null) s,
  ];
  int _index = 0;
  Rect? _hole;
  bool _moving = false;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void initState() {
    super.initState();
    if (_steps.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
    } else {
      _goTo(0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _goTo(int i) async {
    final step = _steps[i];
    setState(() {
      _index = i;
      _moving = step.target != null;
    });
    if (step.target == null) {
      setState(() => _hole = null);
      return;
    }
    final target = Walkthrough._find(step.target!);
    if (target == null) {
      setState(() {
        _hole = null;
        _moving = false;
      });
      return;
    }
    // Bring it on screen first; a tip pointing below the fold is useless.
    try {
      await Scrollable.ensureVisible(
        target.context,
        alignment: 0.35,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
    if (!mounted || _index != i) return;
    setState(() {
      _hole = _rectOf(target);
      _moving = false;
    });
  }

  Rect? _rectOf(_WalkTargetState t) {
    if (!t.mounted) return null;
    final box = t.context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final overlayBox = context.findRenderObject() as RenderBox?;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: null);
    final local =
        overlayBox == null ? topLeft : overlayBox.globalToLocal(topLeft);
    return (local & box.size).inflate(6);
  }

  void _next() {
    if (_moving) return;
    HapticFeedback.selectionClick();
    if (_index + 1 >= _steps.length) {
      _close();
    } else {
      _goTo(_index + 1);
    }
  }

  void _back() {
    if (_moving || _index == 0) return;
    _goTo(_index - 1);
  }

  void _close() {
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_steps.isEmpty) return const SizedBox.shrink();
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final step = _steps[_index];
    final hole = _hole;
    final center =
        Rect.fromCenter(center: size.center(Offset.zero), width: 0, height: 0);

    return PopScope(
      canPop: true,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _next,
                child: TweenAnimationBuilder<Rect?>(
                  tween: RectTween(end: hole ?? center),
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  builder: (context, rect, _) => AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) => CustomPaint(
                      painter: _SpotlightPainter(
                        hole: rect ?? center,
                        pulse: hole == null ? null : _pulse.value,
                        ringColor: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _TipCard(
              key: ValueKey(_index),
              step: step,
              index: _index,
              count: _steps.length,
              hole: _moving ? null : hole,
              screen: size,
              safe: padding,
              onNext: _next,
              onBack: _index == 0 ? null : _back,
              onSkip: _close,
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({required this.hole, this.pulse, required this.ringColor});

  final Rect hole;
  final double? pulse;
  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(math.min(18, hole.shortestSide / 2));
    final rrect = RRect.fromRectAndRadius(hole, radius);
    final scrim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rrect);
    canvas.drawPath(
        scrim, Paint()..color = Colors.black.withValues(alpha: 0.72));

    if (pulse != null && !hole.isEmpty) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = Colors.white.withValues(alpha: 0.9),
      );
      final grow = 10 * pulse!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            hole.inflate(grow), radius + Radius.circular(grow)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = ringColor.withValues(alpha: 0.6 * (1 - pulse!)),
      );
    }
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.hole != hole || old.pulse != pulse || old.ringColor != ringColor;
}

class _TipCard extends StatelessWidget {
  const _TipCard({
    super.key,
    required this.step,
    required this.index,
    required this.count,
    required this.hole,
    required this.screen,
    required this.safe,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  final WalkStep step;
  final int index;
  final int count;
  final Rect? hole;
  final Size screen;
  final EdgeInsets safe;
  final VoidCallback onNext;
  final VoidCallback? onBack;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final last = index == count - 1;
    final width = math.min(screen.width - 32, 380.0);
    final left = (screen.width - width) / 2;

    final card = Material(
      color: cs.surface,
      elevation: 8,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (step.emoji != null) ...[
                  Text(step.emoji!, style: const TextStyle(fontSize: 26)),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      step.title,
                      style:
                          tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                Text(
                  '${index + 1}/$count',
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(width: 6),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              step.body,
              style: tt.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (!last)
                  TextButton(onPressed: onSkip, child: const Text('Skip tour')),
                const Spacer(),
                if (onBack != null)
                  IconButton(
                    tooltip: 'Back',
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: onNext,
                  child: Text(last ? 'Got it' : 'Next'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final h = hole;
    final Widget positioned;
    if (h == null) {
      positioned = Positioned(
        left: left,
        width: width,
        top: 0,
        bottom: 0,
        child: Center(child: card),
      );
    } else {
      final spaceBelow = screen.height - safe.bottom - h.bottom;
      final spaceAbove = h.top - safe.top;
      positioned = spaceBelow >= spaceAbove
          ? Positioned(
              left: left,
              width: width,
              top: h.bottom + 14,
              child: card,
            )
          : Positioned(
              left: left,
              width: width,
              bottom: screen.height - h.top + 14,
              child: card,
            );
    }

    return positioned;
  }
}
