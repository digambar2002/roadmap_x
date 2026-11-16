import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/ai/ai_access.dart';
import '../../../core/subscription/entitlements.dart';
import '../../goals/data/goal_repository.dart';
import '../providers/premium_provider.dart';
import '../../../core/layout/adaptive_sheet.dart';

/// Gates for the paid features.
///
/// Every gate is a soft one: nothing already created is hidden, disabled or
/// deleted when a user is not activated. A lapsed subscription costs you the
/// ability to add more and to sync — never access to what you already wrote.
class PremiumGate {
  const PremiumGate._();

  /// Call before creating a goal. Returns false when the free limit is
  /// reached, having already shown the upsell.
  static Future<bool> ensureGoalSlot(
      BuildContext context, WidgetRef ref) async {
    if (ref.read(isPremiumProvider)) return true;

    final active = await GoalRepository.instance.activeCount();
    if (active < Entitlements.freeActiveGoalLimit) return true;
    if (!context.mounted) return false;

    await _showUpsell(
      context,
      title: 'Goal limit reached',
      message: 'The free tier keeps ${Entitlements.freeActiveGoalLimit} goals '
          'active at once. Archive one to free a slot, or activate '
          '${Entitlements.productName} for unlimited goals.',
    );
    return false;
  }

  /// Call before asking AI to build or organise a plan.
  ///
  /// Anyone with their own key or Premium goes straight through. A free
  /// signed-in account goes through while it has plans left this month.
  /// Someone signed out is offered a free sign-in, not a paywall: the first
  /// AI-built plan is how people find out what the app is for.
  static Future<bool> ensureAi(BuildContext context, WidgetRef ref) async {
    const perMonth = Entitlements.freeAiPlansPerMonth;
    switch (ref.read(aiAccessProvider)) {
      case AiAccess.ownKey:
      case AiAccess.premium:
        return true;
      case AiAccess.free:
        // Unknown (offline, old server) lets them try; the server decides.
        final left = await ref.read(freeAiPlansLeftProvider.future);
        if (left == null || left > 0) return true;
        if (!context.mounted) return false;
        await _showUpsell(
          context,
          title: 'This month\'s free AI plans are used',
          message: 'You get $perMonth AI-built plans a month, and they renew '
              'on the 1st. Until then you can paste a plan or start from a '
              'template. ${Entitlements.productName} includes more.',
        );
        return false;
      case AiAccess.none:
        if (ref.read(syncAvailableProvider)) {
          await _showUpsell(
            context,
            title: 'Let AI build your plan, free',
            message: 'Sign in for free and get $perMonth AI-built plans every '
                'month. No API key or payment needed.',
            actionLabel: 'Sign in free',
          );
        } else {
          await _showUpsell(
            context,
            title: 'Add a Gemini key to use AI',
            message: 'This build has no accounts, so AI runs on your own '
                'free Gemini API key. Add it in Settings → AI coach.',
            actionLabel: 'Open Settings',
            route: '/settings',
          );
        }
        return false;
    }
  }

  static Future<void> _showUpsell(
    BuildContext context, {
    required String title,
    required String message,
    String? actionLabel,
    String route = '/premium',
  }) async {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    await showAdaptiveSheet<void>(
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
                  sheetContext.push(route);
                },
                child: Text(actionLabel ?? 'See ${Entitlements.productName}'),
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
                      style:
                          tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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
