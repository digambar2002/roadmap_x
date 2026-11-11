import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/pet_domain.dart';

/// What the pet is doing right now, besides idling.
enum PetAction { none, eat, drink, play, wash, love }

/// A pet drawn entirely in code, so it needs no image or animation files.
///
/// Always alive: it breathes, blinks and wags. On top of that it plays a
/// short animation for each [PetAction] — chomping food that flies into its
/// mouth, sipping, jumping after a toy, splashing in bubbles, or squishing
/// with hearts when patted. Its face and posture follow [mood].
class PetAvatar extends StatefulWidget {
  const PetAvatar({
    super.key,
    required this.species,
    required this.mood,
    this.action = PetAction.none,
    this.actionNonce = 0,
    this.actionEmoji,
    this.size = 220,
    this.onTap,
    this.animate = true,
  });

  final PetSpecies species;
  final PetMood mood;
  final PetAction action;

  /// Change this to replay [action], even if it is the same as last time.
  final int actionNonce;

  /// The item flying in for eat/drink/play (🐟, 💧, ⚽ …).
  final String? actionEmoji;
  final double size;
  final VoidCallback? onTap;

  /// Off in tests and thumbnails, where looping animations get in the way.
  final bool animate;

  @override
  State<PetAvatar> createState() => _PetAvatarState();
}

class _PetAvatarState extends State<PetAvatar> with TickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
  );
  late final AnimationController _action = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  Timer? _blinkTimer;
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _idle.repeat();
      _scheduleBlink();
    }
    if (widget.action != PetAction.none) _action.forward(from: 0);
  }

  void _scheduleBlink() {
    _blinkTimer?.cancel();
    _blinkTimer = Timer(
      Duration(milliseconds: 2200 + _random.nextInt(3000)),
      () async {
        if (!mounted) return;
        await _blink.forward(from: 0);
        if (!mounted) return;
        await _blink.reverse();
        if (mounted) _scheduleBlink();
      },
    );
  }

  @override
  void didUpdateWidget(covariant PetAvatar old) {
    super.didUpdateWidget(old);
    if (widget.actionNonce != old.actionNonce &&
        widget.action != PetAction.none) {
      _action.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _idle.dispose();
    _blink.dispose();
    _action.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: s,
        height: s,
        child: AnimatedBuilder(
          animation: Listenable.merge([_idle, _blink, _action]),
          builder: (context, _) {
            final acting = _action.isAnimating || _action.value < 1;
            final action = acting ? widget.action : PetAction.none;
            final t = _action.value;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _PetPainter(
                      species: widget.species,
                      mood: widget.mood,
                      idle: _idle.value,
                      blink: _blink.value,
                      action: action,
                      t: t,
                    ),
                  ),
                ),
                ..._overlay(action, t, s),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Emoji effects that sit over the drawing: the item flying in, hearts,
  /// sleepy z's.
  List<Widget> _overlay(PetAction action, double t, double s) {
    final out = <Widget>[];
    final emoji = widget.actionEmoji;

    if ((action == PetAction.eat ||
            action == PetAction.drink ||
            action == PetAction.play) &&
        emoji != null &&
        t < 0.55) {
      // Arc from bottom-right into the mouth, shrinking as it is eaten.
      final p = (t / 0.55).clamp(0.0, 1.0);
      final start = Offset(s * 0.86, s * 0.86);
      final end = action == PetAction.play
          ? Offset(s * 0.5, s * 0.08)
          : Offset(s * 0.5, s * 0.5);
      final x = start.dx + (end.dx - start.dx) * p;
      final y =
          start.dy + (end.dy - start.dy) * p - math.sin(p * math.pi) * s * 0.2;
      final size = s * 0.16 * (action == PetAction.play ? 1 : (1 - p * 0.6));
      out.add(Positioned(
        left: x - size / 2,
        top: y - size / 2,
        child: Opacity(
          opacity: action == PetAction.play ? 1 : (1 - p * 0.7),
          child: Text(emoji, style: TextStyle(fontSize: size)),
        ),
      ));
    }

    if (action == PetAction.love || (action == PetAction.eat && t > 0.55)) {
      for (var i = 0; i < 3; i++) {
        final p = ((t - i * 0.12) / 0.8).clamp(0.0, 1.0);
        if (p <= 0) continue;
        out.add(Positioned(
          left: s * (0.28 + i * 0.22),
          top: s * (0.22 - p * 0.22),
          child: Opacity(
            opacity: 1 - p,
            child: Text('❤️', style: TextStyle(fontSize: s * 0.09)),
          ),
        ));
      }
    }

    if (widget.mood == PetMood.tired && action == PetAction.none) {
      final p = _idle.value;
      out.add(Positioned(
        left: s * (0.7 + p * 0.06),
        top: s * (0.18 - p * 0.08),
        child: Opacity(
          opacity: 1 - p,
          child: Text(
            'z',
            style: TextStyle(
              fontSize: s * 0.08,
              fontWeight: FontWeight.w800,
              color: Colors.blueGrey,
            ),
          ),
        ),
      ));
    }
    return out;
  }
}

class _PetPainter extends CustomPainter {
  _PetPainter({
    required this.species,
    required this.mood,
    required this.idle,
    required this.blink,
    required this.action,
    required this.t,
  });

  final PetSpecies species;
  final PetMood mood;
  final double idle;
  final double blink;
  final PetAction action;
  final double t;

  static const _ink = Color(0xFF2B2B2B);
  static const _pink = Color(0xFFF7A8C4);

  double get _breathe => (math.sin(idle * 2 * math.pi) + 1) / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final info = speciesInfo[species]!;
    final low = mood == PetMood.tired || mood == PetMood.unwell;

    canvas.save();
    // Whole-body motion for actions and mood.
    final cx = s / 2;
    switch (action) {
      case PetAction.play:
        final jump = math.sin(t * math.pi);
        canvas.translate(0, -jump * s * 0.16);
        canvas.translate(cx, s * 0.7);
        canvas.rotate(math.sin(t * math.pi * 2) * 0.12);
        canvas.translate(-cx, -s * 0.7);
      case PetAction.love:
        final squish = math.sin(t * math.pi * 4) * (1 - t) * 0.1;
        canvas.translate(cx, s * 0.92);
        canvas.scale(1 + squish, 1 - squish);
        canvas.translate(-cx, -s * 0.92);
      case PetAction.wash:
        canvas.translate(math.sin(t * math.pi * 10) * s * 0.012 * (1 - t), 0);
      case PetAction.eat:
      case PetAction.drink:
      case PetAction.none:
        break;
    }
    if (low && action == PetAction.none) {
      canvas.translate(cx, s * 0.92);
      canvas.rotate(mood == PetMood.unwell ? -0.07 : -0.03);
      canvas.translate(-cx, -s * 0.92);
    }

    // Ground shadow.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, s * 0.93),
        width: s * (0.5 - _breathe * 0.02),
        height: s * 0.06,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.12),
    );

    final breathe = low ? _breathe * 0.4 : _breathe;
    final bodyCenter = Offset(cx, s * 0.72);
    final bodyW = s * 0.5;
    final bodyH = s * 0.34 * (1 + breathe * 0.03);
    final headDrop = action == PetAction.drink
        ? math.sin(math.min(t / 0.6, 1) * math.pi) * s * 0.03
        : 0.0;
    final head = Offset(
        cx, s * 0.42 - breathe * s * 0.008 + headDrop + (low ? s * 0.02 : 0));
    final headR = s * 0.25;

    final bodyPaint = Paint()..color = info.body;
    final bellyPaint = Paint()..color = info.belly;
    final accentPaint = Paint()..color = info.accent;
    final inkPaint = Paint()..color = _ink;

    // ── Tail (behind body) ───────────────────────────────
    _tail(canvas, s, bodyCenter, info, low);

    // ── Dino spikes (behind head and body) ───────────────
    if (species == PetSpecies.dino) {
      for (var i = 0; i < 4; i++) {
        final a = -math.pi / 2 + 0.55 + i * 0.42;
        final base = head + Offset(math.cos(a), math.sin(a)) * headR * 0.92;
        final tip = head + Offset(math.cos(a), math.sin(a)) * headR * 1.28;
        final side = Offset(-math.sin(a), math.cos(a)) * s * 0.035;
        canvas.drawPath(
          Path()
            ..moveTo(base.dx - side.dx, base.dy - side.dy)
            ..lineTo(tip.dx, tip.dy)
            ..lineTo(base.dx + side.dx, base.dy + side.dy)
            ..close(),
          accentPaint,
        );
      }
    }

    // ── Feet ─────────────────────────────────────────────
    final feetPaint =
        species == PetSpecies.panda ? inkPaint : (Paint()..color = info.body);
    for (final dx in [-0.13, 0.13]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + dx * s, s * 0.885),
          width: s * 0.14,
          height: s * 0.08,
        ),
        feetPaint,
      );
    }

    // ── Body and belly ───────────────────────────────────
    canvas.drawOval(
        Rect.fromCenter(center: bodyCenter, width: bodyW, height: bodyH),
        bodyPaint);
    canvas.drawOval(
      Rect.fromCenter(
        center: bodyCenter + Offset(0, s * 0.02),
        width: bodyW * 0.6,
        height: bodyH * 0.7,
      ),
      bellyPaint,
    );

    // ── Arms ─────────────────────────────────────────────
    final armPaint = species == PetSpecies.panda ? inkPaint : bodyPaint;
    final wave =
        action == PetAction.play ? math.sin(t * math.pi * 6) * 0.4 : 0.0;
    for (final side in [-1, 1]) {
      canvas.save();
      canvas.translate(cx + side * bodyW * 0.42, bodyCenter.dy - bodyH * 0.15);
      canvas.rotate(side * (0.5 + wave));
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(0, s * 0.05), width: s * 0.09, height: s * 0.16),
        armPaint,
      );
      canvas.restore();
    }

    // ── Ears (behind head) ───────────────────────────────
    _ears(canvas, s, head, headR, info);

    // ── Head ─────────────────────────────────────────────
    canvas.drawCircle(head, headR, bodyPaint);
    _frontEars(canvas, head, headR, info);

    // Panda eye patches; puppy patch.
    final eyeY = head.dy - headR * 0.02;
    final eyeDx = headR * 0.4;
    if (species == PetSpecies.panda) {
      for (final side in [-1, 1]) {
        canvas.save();
        canvas.translate(cx + side * eyeDx, eyeY + headR * 0.04);
        canvas.rotate(side * -0.5);
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset.zero, width: headR * 0.42, height: headR * 0.56),
          inkPaint,
        );
        canvas.restore();
      }
    } else if (species == PetSpecies.dog) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + eyeDx, eyeY - headR * 0.02),
          width: headR * 0.5,
          height: headR * 0.48,
        ),
        accentPaint,
      );
    }

    // Muzzle for the dog and cat.
    if (species == PetSpecies.dog || species == PetSpecies.cat) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, head.dy + headR * 0.38),
          width: headR * 0.8,
          height: headR * 0.48,
        ),
        bellyPaint,
      );
    }

    // ── Eyes ─────────────────────────────────────────────
    _eyes(canvas, s, Offset(cx, eyeY), eyeDx, headR);

    // ── Cheeks ───────────────────────────────────────────
    if (mood != PetMood.unwell) {
      final cheek = Paint()..color = _pink.withValues(alpha: 0.55);
      for (final side in [-1, 1]) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(cx + side * headR * 0.62, head.dy + headR * 0.3),
            width: headR * 0.26,
            height: headR * 0.15,
          ),
          cheek,
        );
      }
    }

    // ── Nose ─────────────────────────────────────────────
    final noseY = head.dy + headR * 0.24;
    if (species == PetSpecies.dino) {
      for (final side in [-1, 1]) {
        canvas.drawCircle(
            Offset(cx + side * headR * 0.1, noseY), headR * 0.03, inkPaint);
      }
    } else {
      final noseW = species == PetSpecies.dog ? 0.22 : 0.13;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, noseY),
          width: headR * noseW,
          height: headR * noseW * 0.7,
        ),
        Paint()..color = species == PetSpecies.cat ? _pink : _ink,
      );
    }

    // ── Mouth ────────────────────────────────────────────
    _mouth(canvas, s, Offset(cx, head.dy + headR * 0.44), headR);

    // Whiskers.
    if (species == PetSpecies.cat) {
      final w = Paint()
        ..color = _ink.withValues(alpha: 0.5)
        ..strokeWidth = s * 0.006
        ..strokeCap = StrokeCap.round;
      for (final side in [-1, 1]) {
        for (final dy in [-0.06, 0.04]) {
          canvas.drawLine(
            Offset(cx + side * headR * 0.42, noseY + dy * headR),
            Offset(cx + side * headR * 0.95, noseY + dy * headR * 2.2),
            w,
          );
        }
      }
    }

    // Bunny teeth.
    if (species == PetSpecies.bunny && action != PetAction.eat) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx, head.dy + headR * 0.56),
            width: headR * 0.18,
            height: headR * 0.14,
          ),
          Radius.circular(headR * 0.03),
        ),
        Paint()..color = Colors.white,
      );
    }

    // Sweat drop when unwell.
    if (mood == PetMood.unwell) {
      final drop = Offset(cx + headR * 0.78, head.dy - headR * 0.35);
      canvas.drawPath(
        Path()
          ..moveTo(drop.dx, drop.dy - headR * 0.14)
          ..quadraticBezierTo(
              drop.dx + headR * 0.1, drop.dy, drop.dx, drop.dy + headR * 0.06)
          ..quadraticBezierTo(
              drop.dx - headR * 0.1, drop.dy, drop.dx, drop.dy - headR * 0.14),
        Paint()..color = const Color(0xFF7CC4FF),
      );
    }

    // ── Bubbles while washing ────────────────────────────
    if (action == PetAction.wash) {
      final bubble = Paint()
        ..color = const Color(0xFFBFE6FF).withValues(alpha: 0.75);
      final rim = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.004;
      for (var i = 0; i < 9; i++) {
        final p = ((t * 1.4) - i * 0.07).clamp(0.0, 1.0);
        if (p <= 0 || p >= 1) continue;
        final x = s * (0.2 + (i * 0.37) % 0.6) + math.sin(p * 6 + i) * s * 0.02;
        final y = s * (0.9 - p * 0.75);
        final r = s * (0.025 + (i % 3) * 0.012);
        canvas.drawCircle(Offset(x, y), r, bubble);
        canvas.drawCircle(Offset(x, y), r, rim);
      }
    }

    canvas.restore();
  }

  void _tail(Canvas canvas, double s, Offset body, SpeciesInfo info, bool low) {
    final wagSpeed = species == PetSpecies.dog ? 4 : 1;
    final wag = math.sin(idle * 2 * math.pi * wagSpeed) * (low ? 0.05 : 0.25);
    final paint = Paint()..color = info.body;
    final base = body + Offset(s * 0.22, s * 0.04);
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(wag);
    switch (species) {
      case PetSpecies.cat:
        canvas.drawPath(
          Path()
            ..moveTo(0, 0)
            ..quadraticBezierTo(s * 0.18, -s * 0.02, s * 0.14, -s * 0.2),
          Paint()
            ..color = info.body
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.05
            ..strokeCap = StrokeCap.round,
        );
      case PetSpecies.dog:
        canvas.drawPath(
          Path()
            ..moveTo(0, 0)
            ..quadraticBezierTo(s * 0.1, -s * 0.02, s * 0.1, -s * 0.12),
          Paint()
            ..color = info.accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.045
            ..strokeCap = StrokeCap.round,
        );
      case PetSpecies.bunny:
        canvas.drawCircle(
            Offset(s * 0.02, 0), s * 0.055, Paint()..color = Colors.white);
      case PetSpecies.panda:
        canvas.drawCircle(Offset(s * 0.01, 0), s * 0.04, Paint()..color = _ink);
      case PetSpecies.dino:
        canvas.drawPath(
          Path()
            ..moveTo(-s * 0.02, -s * 0.06)
            ..quadraticBezierTo(s * 0.2, -s * 0.02, s * 0.26, s * 0.08)
            ..quadraticBezierTo(s * 0.12, s * 0.08, -s * 0.02, s * 0.06)
            ..close(),
          paint,
        );
    }
    canvas.restore();
  }

  void _ears(Canvas canvas, double s, Offset head, double r, SpeciesInfo info) {
    final body = Paint()..color = info.body;
    final inner = Paint()..color = _pink;
    switch (species) {
      case PetSpecies.cat:
        for (final side in [-1, 1]) {
          final base = head + Offset(side * r * 0.55, -r * 0.62);
          canvas.drawPath(
            Path()
              ..moveTo(base.dx - side * r * 0.35, base.dy + r * 0.2)
              ..lineTo(base.dx + side * r * 0.1, base.dy - r * 0.55)
              ..lineTo(base.dx + side * r * 0.42, base.dy + r * 0.1)
              ..close(),
            body,
          );
          canvas.drawPath(
            Path()
              ..moveTo(base.dx - side * r * 0.18, base.dy + r * 0.12)
              ..lineTo(base.dx + side * r * 0.08, base.dy - r * 0.32)
              ..lineTo(base.dx + side * r * 0.26, base.dy + r * 0.08)
              ..close(),
            inner,
          );
        }
      case PetSpecies.dog:
        // Floppy ears hang over the head: see [_frontEars].
        break;
      case PetSpecies.bunny:
        final sway = math.sin(idle * 2 * math.pi) * 0.05;
        for (final side in [-1, 1]) {
          canvas.save();
          canvas.translate(head.dx + side * r * 0.38, head.dy - r * 0.75);
          canvas.rotate(side * (0.12 + sway));
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(0, -r * 0.32),
                  width: r * 0.42,
                  height: r * 0.92),
              Radius.circular(r * 0.21),
            ),
            body,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(0, -r * 0.3),
                  width: r * 0.2,
                  height: r * 0.66),
              Radius.circular(r * 0.1),
            ),
            inner,
          );
          canvas.restore();
        }
      case PetSpecies.panda:
        for (final side in [-1, 1]) {
          canvas.drawCircle(
            head + Offset(side * r * 0.72, -r * 0.72),
            r * 0.28,
            Paint()..color = _ink,
          );
        }
      case PetSpecies.dino:
        break;
    }
  }

  void _frontEars(Canvas canvas, Offset head, double r, SpeciesInfo info) {
    if (species != PetSpecies.dog) return;
    final flop = math.sin(idle * 2 * math.pi) * 0.08;
    for (final side in [-1, 1]) {
      canvas.save();
      canvas.translate(head.dx + side * r * 0.86, head.dy - r * 0.42);
      canvas.rotate(side * (0.22 + flop));
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(0, r * 0.42), width: r * 0.48, height: r * 0.92),
        Paint()..color = info.accent,
      );
      canvas.restore();
    }
  }

  void _eyes(Canvas canvas, double s, Offset center, double dx, double r) {
    final ink = Paint()
      ..color = species == PetSpecies.panda ? Colors.white : _ink;
    final happyFace = action == PetAction.love ||
        (action == PetAction.eat && t > 0.55) ||
        (mood == PetMood.happy && action == PetAction.play);
    final eyeR = r * 0.12;

    for (final side in [-1, 1]) {
      final c = center + Offset(side * dx, 0);
      if (happyFace) {
        // Closed, smiling eyes: ^ ^
        canvas.drawArc(
          Rect.fromCenter(
              center: c + Offset(0, eyeR * 0.4),
              width: eyeR * 2.2,
              height: eyeR * 2),
          math.pi,
          math.pi,
          false,
          Paint()
            ..color = ink.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.012
            ..strokeCap = StrokeCap.round,
        );
        continue;
      }
      final lid = mood == PetMood.unwell
          ? 0.55
          : mood == PetMood.tired
              ? 0.4
              : 0.0;
      final open = (1 - blink) * (1 - lid);
      canvas.drawOval(
        Rect.fromCenter(
          center: c,
          width: eyeR * 2,
          height: math.max(eyeR * 2 * open, s * 0.008),
        ),
        ink,
      );
      if (open > 0.5) {
        canvas.drawCircle(
          c + Offset(-eyeR * 0.3, -eyeR * 0.35),
          eyeR * 0.32,
          Paint()..color = species == PetSpecies.panda ? _ink : Colors.white,
        );
      }
      // Worried brows when sad or worse.
      if (mood == PetMood.sad ||
          mood == PetMood.tired ||
          mood == PetMood.unwell) {
        final browY = c.dy - eyeR * 1.9;
        canvas.drawLine(
          Offset(c.dx - side * eyeR * 1.1, browY - eyeR * 0.5),
          Offset(c.dx + side * eyeR * 0.9, browY + eyeR * 0.2),
          Paint()
            ..color = _ink.withValues(alpha: 0.7)
            ..strokeWidth = s * 0.01
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // A tear when unwell.
    if (mood == PetMood.unwell && action == PetAction.none) {
      final tear = center + Offset(-dx, eyeR * 1.6 + idle * r * 0.2);
      canvas.drawCircle(
        tear,
        r * 0.05,
        Paint()..color = const Color(0xFF7CC4FF).withValues(alpha: 1 - idle),
      );
    }
  }

  void _mouth(Canvas canvas, double s, Offset c, double r) {
    final stroke = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.011
      ..strokeCap = StrokeCap.round;

    if (action == PetAction.eat && t < 0.75) {
      // Chomp: open and close quickly.
      final open = (math.sin(t * math.pi * 10).abs()) * r * 0.22 + r * 0.04;
      canvas.drawOval(
        Rect.fromCenter(center: c, width: r * 0.3, height: open),
        Paint()..color = const Color(0xFF8B2E3C),
      );
      return;
    }
    if (action == PetAction.drink && t < 0.8) {
      canvas.drawCircle(c, r * 0.07, Paint()..color = const Color(0xFF8B2E3C));
      return;
    }

    final happy = mood == PetMood.happy ||
        mood == PetMood.content ||
        action == PetAction.love ||
        action == PetAction.play;
    final w = r * 0.42;
    if (happy) {
      // A little "w" smile.
      final path = Path()
        ..moveTo(c.dx - w / 2, c.dy - r * 0.04)
        ..quadraticBezierTo(
            c.dx - w / 4, c.dy + r * 0.12, c.dx, c.dy - r * 0.02)
        ..quadraticBezierTo(
            c.dx + w / 4, c.dy + r * 0.12, c.dx + w / 2, c.dy - r * 0.04);
      canvas.drawPath(path, stroke);
      if (action == PetAction.love || mood == PetMood.happy) {
        canvas.drawOval(
          Rect.fromCenter(
              center: c + Offset(0, r * 0.09),
              width: r * 0.14,
              height: r * 0.1),
          Paint()..color = _pink,
        );
      }
    } else {
      // Frown.
      canvas.drawArc(
        Rect.fromCenter(
            center: c + Offset(0, r * 0.12), width: w * 0.8, height: r * 0.22),
        math.pi * 1.15,
        math.pi * 0.7,
        false,
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PetPainter old) =>
      old.idle != idle ||
      old.blink != blink ||
      old.t != t ||
      old.action != action ||
      old.mood != mood ||
      old.species != species;
}
