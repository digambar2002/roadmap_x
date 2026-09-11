import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../layout/breakpoints.dart';

class AppShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  void _onTabTap(int index) {
    // Haptics exist on touch devices only; on desktop this is a no-op, but
    // asking for it there is noise either way.
    if (!isPointerPlatform) HapticFeedback.selectionClick();
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.navigationShell.currentIndex;

    // Once there is width to spare, navigation belongs at the side: it frees
    // the bottom edge, puts the targets near where a cursor already is, and
    // stops five tabs stretching across a monitor.
    if (context.usesSideNav) {
      return Scaffold(
        body: Row(
          children: [
            _SideNav(
              currentIndex: index,
              onTap: _onTabTap,
              extended: context.isExpanded,
            ),
            Expanded(child: widget.navigationShell),
          ],
        ),
      );
    }

    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: _BottomNav(currentIndex: index, onTap: _onTabTap),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

const _navItems = [
  _NavItem(icon: Icons.home_rounded, label: 'Home'),
  _NavItem(icon: Icons.today_rounded, label: 'Today'),
  _NavItem(icon: Icons.flag_rounded, label: 'Goals'),
  _NavItem(icon: Icons.calendar_month_rounded, label: 'Schedule'),
  _NavItem(icon: Icons.bar_chart_rounded, label: 'Stats'),
];

// ── Side navigation (medium and expanded) ─────────────────

class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.currentIndex,
    required this.onTap,
    required this.extended,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Labels beside the icons rather than under them.
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      width: extended ? 216 : 76,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(right: BorderSide(color: cs.outline)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(extended ? 20 : 0, 20, 0, 20),
              child: extended
                  ? Text(
                      'RoadmapX',
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    )
                  : Icon(Icons.flag_rounded, color: cs.primary, size: 24),
            ),
            for (var i = 0; i < _navItems.length; i++)
              _SideNavTab(
                item: _navItems[i],
                selected: currentIndex == i,
                extended: extended,
                onTap: () => onTap(i),
              ),
            const Spacer(),
            _SideNavTab(
              item: const _NavItem(
                icon: Icons.settings_outlined,
                label: 'Settings',
              ),
              selected: false,
              extended: extended,
              onTap: () => context.push('/settings'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _SideNavTab extends StatelessWidget {
  const _SideNavTab({
    required this.item,
    required this.selected,
    required this.extended,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? cs.primary : cs.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Tooltip(
        message: extended ? '' : item.label,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 44,
            padding: EdgeInsets.symmetric(horizontal: extended ? 14 : 0),
            decoration: BoxDecoration(
              // Same pill highlight the bottom bar uses, so the two layouts
              // read as one app.
              color: selected
                  ? cs.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment:
                  extended ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Icon(item.icon, color: color, size: 21),
                if (extended) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                        color: color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Bottom navigation (compact) ───────────────────────────

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outline, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(
              _navItems.length,
              (i) => Expanded(
                child: _NavTab(
                  item: _navItems[i],
                  selected: currentIndex == i,
                  onTap: () => onTap(i),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavTab({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? cs.primary : cs.onSurfaceVariant;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: selected
                  ? cs.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, color: color, size: 22),
          ),
          const SizedBox(height: 2),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: color,
            ),
            child: Text(item.label),
          ),
        ],
      ),
    );
  }
}
