import 'package:flutter/material.dart';

/// Greeting, date, and the two creation actions.
///
/// These actions used to sit below the fold as a full-width AI card and a
/// separate chip, which cost most of the first screen before any of the user's
/// own data appeared. As icon buttons they cost nothing and stay reachable.
class DashboardHeader extends StatelessWidget {
  const DashboardHeader({
    super.key,
    required this.greeting,
    required this.date,
    required this.onNewGoal,
    required this.onGenerateWithAi,
  });

  final String greeting;
  final String date;
  final VoidCallback onNewGoal;
  final VoidCallback onGenerateWithAi;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                date,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _HeaderAction(
          icon: Icons.add_rounded,
          tooltip: 'New goal',
          onPressed: onNewGoal,
        ),
        const SizedBox(width: 6),
        _HeaderAction(
          icon: Icons.auto_awesome,
          tooltip: 'Generate with AI',
          onPressed: onGenerateWithAi,
          gradient: const LinearGradient(
            colors: [Color(0xFF5B9CF6), Color(0xFFA78BFA)],
          ),
        ),
      ],
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.gradient,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final child = Icon(
      icon,
      size: 20,
      color: gradient != null ? Colors.white : cs.onSurfaceVariant,
    );

    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Container(
          height: 38,
          width: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outline),
            color: cs.surfaceContainerHighest,
          ),
          child: gradient == null
              ? child
              : ShaderMask(
                  shaderCallback: (bounds) => gradient!.createShader(bounds),
                  child: child,
                ),
        ),
      ),
    );
  }
}
