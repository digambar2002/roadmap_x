import 'package:flutter/material.dart';

class ProgressBar extends StatefulWidget {
  final double percent; // 0.0 – 1.0
  final Color color;
  final double height;
  final bool animate;
  final BorderRadius? borderRadius;

  const ProgressBar({
    super.key,
    required this.percent,
    required this.color,
    this.height = 6,
    this.animate = true,
    this.borderRadius,
  });

  @override
  State<ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<ProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _animation = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    if (widget.animate) _ctrl.forward();
  }

  @override
  void didUpdateWidget(ProgressBar old) {
    super.didUpdateWidget(old);
    if (old.percent != widget.percent && widget.animate) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final br = widget.borderRadius ?? BorderRadius.circular(widget.height / 2);
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final total = constraints.maxWidth;
          final filled = total * (widget.percent * _animation.value);
          return Container(
            height: widget.height,
            decoration: BoxDecoration(
              color: widget.color.withOpacity(0.12),
              borderRadius: br,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: filled,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [widget.color.withOpacity(0.7), widget.color],
                  ),
                  borderRadius: br,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
