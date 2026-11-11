import 'package:flutter/material.dart';

/// Large page title, with a back button whenever the page was pushed.
///
/// Tab roots have nothing to go back to and show only the title; screens
/// opened from a tab (Insights, Schedule, Tasks) get the arrow automatically,
/// so iOS users, who have no system back button, are never stranded.
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final canPop = Navigator.of(context).canPop();
    return Row(
      children: [
        if (canPop) ...[
          const BackButton(),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
