import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AnimatedCheckbox extends StatefulWidget {
  final bool checked;
  final Color color;
  final VoidCallback onToggle;
  final double size;

  const AnimatedCheckbox({
    super.key,
    required this.checked,
    required this.color,
    required this.onToggle,
    this.size = 22,
  });

  @override
  State<AnimatedCheckbox> createState() => _AnimatedCheckboxState();
}

class _AnimatedCheckboxState extends State<AnimatedCheckbox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _checkAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.2), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 60),
    ]).animate(_ctrl);
    _checkAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    if (widget.checked) _ctrl.value = 1.0;
  }

  @override
  void didUpdateWidget(AnimatedCheckbox old) {
    super.didUpdateWidget(old);
    if (old.checked != widget.checked) {
      if (widget.checked) {
        _ctrl.forward(from: 0);
      } else {
        _ctrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onToggle();
      },
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Transform.scale(
          scale: _scaleAnim.value,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: widget.checked ? widget.color : cs.outline,
                width: 1.5,
              ),
              color: widget.checked ? widget.color : Colors.transparent,
            ),
            child: widget.checked
                ? CustomPaint(
                    painter: _CheckPainter(
                      progress: _checkAnim.value,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  final double progress;
  final Color color;
  _CheckPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(size.width * 0.2, size.height * 0.5)
      ..lineTo(size.width * 0.42, size.height * 0.7)
      ..lineTo(size.width * 0.8, size.height * 0.28);

    final metrics = path.computeMetrics().first;
    final drawn = metrics.extractPath(0, metrics.length * progress);
    canvas.drawPath(drawn, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress;
}
