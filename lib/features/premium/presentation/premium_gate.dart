import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/subscription/entitlements.dart';
import '../../goals/data/goal_repository.dart';
import '../providers/premium_provider.dart';

/// Gates for the paid features.
///
/// Every gate is a soft one: nothing already created is hidden, disabled or
/// deleted when a user is not activated. A lapsed subscription costs you the
/// ability to add more and to sync — never access to what you already wrote.
class PremiumGate {
  const PremiumGate._();

  /// Call before creating a goal. Returns false when the free limit is
  /// reached, having already shown the upsell.
  static Future<bool> ensureGoalSlot(BuildContext context, WidgetRef ref) async {
    if (ref.read(isPremiumProvider)) return true;

    final active = await GoalRepository.instance.activeCount();
    if (active < Entitlements.freeActiveGoalLimit) return true;
    if (!context.mounted) return false;

    await _showUpsell(
      context,
      title: 'Goal limit reached',
      message:
          'The free tier keeps ${Entitlements.freeActiveGoalLimit} goals '
          'active at once. Archive one to free a slot, or activate '
          '${Entitlements.productName} for unlimited goals.',
    );
    return false;
  }

  /// Call before opening an AI feature.
  static Future<bool> ensureAi(BuildContext context, WidgetRef ref) async {
    if (ref.read(isPremiumProvider)) return true;

    await _showUpsell(
      context,
      title: 'AI coach is a premium feature',
      message:
          'Daily briefings, weekly reviews and AI-built plans come with '
          '${Entitlements.productName}.',
    );
    return false;
  }

  static Future<void> _showUpsell(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  sheetContext.push('/premium');
                },
                child: Text('See ${Entitlements.productName}'),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('Not now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows [child] to activated accounts, and a tappable placeholder otherwise.
///
/// Used for AI panels that sit inline in a screen, where a dialog would be the
/// wrong shape — the section keeps its place in the layout and explains itself
/// rather than silently vanishing.
class PremiumLock extends ConsumerWidget {
  const PremiumLock({
    super.key,
    required this.child,
    required this.title,
    required this.message,
  });

  final Widget child;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isPremiumProvider)) return child;

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.push('/premium'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outline),
          color: cs.surfaceContainerHighest,
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: tt.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
