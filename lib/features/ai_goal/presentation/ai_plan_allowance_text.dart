import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/ai/ai_access.dart';
import '../../../core/subscription/entitlements.dart';

/// One line under an "AI builds your plan" option saying what it costs this
/// user: nothing, with how many free plans are left when that applies.
class AiPlanAllowanceText extends ConsumerWidget {
  const AiPlanAllowanceText({super.key, this.style, this.textAlign});

  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const perMonth = Entitlements.freeAiPlansPerMonth;
    final access = ref.watch(aiAccessProvider);
    final left = ref.watch(freeAiPlansLeftProvider).valueOrNull;
    final text = switch (access) {
      AiAccess.none => 'Free with sign-in: $perMonth AI plans a month',
      AiAccess.free => left == null
          ? 'Free: $perMonth AI plans a month'
          : left == 0
              ? 'No free AI plans left this month'
              : '$left of $perMonth free AI plans left this month',
      AiAccess.ownKey ||
      AiAccess.premium =>
        'Describe your goal, AI builds the plan',
    };
    return Text(text, style: style, textAlign: textAlign);
  }
}
