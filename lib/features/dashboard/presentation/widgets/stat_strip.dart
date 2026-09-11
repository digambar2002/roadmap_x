import 'package:flutter/material.dart';

/// One tappable number.
class DashboardStat {
  const DashboardStat({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
    this.isMuted = false,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  /// Draws in grey. Used for a zero that is good news — no overdue work is
  /// not something to colour in alarm red.
  final bool isMuted;
}

/// The row of headline numbers that opens the dashboard.
///
/// Each tile is a route into the screen that can act on it, so the numbers are
/// navigation rather than decoration.
class StatStrip extends StatelessWidget {
  const StatStrip({super.key, required this.stats});

  final List<DashboardStat> stats;

  @override
  Widget build(BuildContext context) {
    // IntrinsicHeight is what makes the tiles equal height here. A bare
    // `CrossAxisAlignment.stretch` cannot: this sits in a CustomScrollView
    // sliver, where the incoming height is unbounded, and stretching to an
    // unbounded cross axis throws "BoxConstraints forces an infinite height"
    // — which aborts layout for the whole viewport, blanking the page.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _StatTile(stat: stats[i])),
          ],
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});

  final DashboardStat stat;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final accent = stat.isMuted ? cs.onSurfaceVariant : stat.color;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: stat.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: stat.isMuted ? cs.outline : accent.withValues(alpha: 0.35),
          ),
          color: stat.isMuted
              ? cs.surfaceContainerHighest
              : accent.withValues(alpha: 0.10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(stat.icon, size: 16, color: accent),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                stat.value,
                style: tt.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: accent,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              stat.label,
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
