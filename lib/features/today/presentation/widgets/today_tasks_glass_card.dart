import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/today_task.dart';
import '../../../tasks/providers/task_provider.dart';

/// A sleek glassmorphic card widget displaying the user's tasks for today.
/// Features a frosted-glass blur, subtle border highlights, glowing badges,
/// and live task state.
class TodayTasksGlassCard extends ConsumerWidget {
  final VoidCallback? onHeaderTap;
  final void Function(TodayTaskContext taskCtx)? onTaskTap;

  const TodayTasksGlassCard({
    super.key,
    this.onHeaderTap,
    this.onTaskTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(todayTasksGroupedProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final dateFormatted = DateFormat('EEE, MMM d').format(DateTime.now());

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      const Color(0xFF1E293B).withValues(alpha: 0.70),
                      const Color(0xFF0F172A).withValues(alpha: 0.85),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.80),
                      Colors.white.withValues(alpha: 0.60),
                    ],
            ),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.60),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ───────────────────────────────────────────
              InkWell(
                onTap: onHeaderTap,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF6366F1).withValues(alpha: 0.20),
                          border: Border.all(
                            color: const Color(0xFF818CF8).withValues(alpha: 0.50),
                            width: 1.2,
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.check_circle_outline_rounded,
                            size: 18,
                            color: Color(0xFF818CF8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Today's Tasks",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                                letterSpacing: -0.2,
                              ),
                            ),
                            Text(
                              dateFormatted,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      tasksAsync.maybeWhen(
                        data: (data) => _CountBadge(
                          count: data.actionableCount,
                          isDark: isDark,
                        ),
                        orElse: () => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Divider ──────────────────────────────────────────
              Divider(
                height: 1,
                thickness: 1,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.black.withValues(alpha: 0.06),
              ),

              // ── Task List / Empty State ──────────────────────────
              tasksAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(28.0),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Error: $e', style: const TextStyle(fontSize: 12)),
                ),
                data: (data) {
                  final tasks = [
                    ...data.overdue,
                    ...data.dueToday,
                    ...data.thisWeek,
                  ];

                  if (tasks.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('✨', style: TextStyle(fontSize: 28)),
                          const SizedBox(height: 6),
                          Text(
                            'All caught up!',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'No tasks due today.',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    itemCount: tasks.length > 5 ? 5 : tasks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = tasks[index];
                      return _GlassTaskItem(
                        taskCtx: item,
                        isDark: isDark,
                        onTap: () => onTaskTap?.call(item),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  final bool isDark;

  const _CountBadge({required this.count, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final text = count == 0 ? 'All Clear ✨' : (count == 1 ? '1 task' : '$count tasks');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF818CF8).withValues(alpha: 0.40),
          width: 1,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isDark ? const Color(0xFFC7D2FE) : const Color(0xFF4338CA),
        ),
      ),
    );
  }
}

class _GlassTaskItem extends StatelessWidget {
  final TodayTaskContext taskCtx;
  final bool isDark;
  final VoidCallback? onTap;

  const _GlassTaskItem({
    required this.taskCtx,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final task = taskCtx.task;
    final goalTitle = taskCtx.goal?.name ?? taskCtx.milestone?.title;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.05),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF818CF8).withValues(alpha: 0.60),
                    width: 1.6,
                  ),
                  color: Colors.transparent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    if (goalTitle != null && goalTitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          goalTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _TaskStatusBadge(taskCtx: taskCtx, isDark: isDark),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskStatusBadge extends StatelessWidget {
  final TodayTaskContext taskCtx;
  final bool isDark;

  const _TaskStatusBadge({required this.taskCtx, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (taskCtx.isOverdue) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: const Color(0xFFF43F5E).withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFFFB7185).withValues(alpha: 0.50),
            width: 1,
          ),
        ),
        child: const Text(
          'Overdue',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFFFDA4AF),
          ),
        ),
      );
    }

    if (taskCtx.isDueToday) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: const Color(0xFF0EA5E9).withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFF38BDF8).withValues(alpha: 0.50),
            width: 1,
          ),
        ),
        child: const Text(
          'Today',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFFBAE6FD),
          ),
        ),
      );
    }

    if (taskCtx.dueDate != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.40),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withValues(alpha: isDark ? 0.15 : 0.30),
            width: 1,
          ),
        ),
        child: Text(
          DateFormat('MMM d').format(taskCtx.dueDate!),
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
