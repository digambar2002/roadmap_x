import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../router/app_shell.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/today/presentation/today_screen.dart';
import '../../features/goals/presentation/goals_screen.dart';
import '../../features/goals/presentation/goal_detail_screen.dart';
import '../../features/focus/presentation/focus_screen.dart';
import '../../features/schedule/presentation/schedule_screen.dart';
import '../../features/analytics/presentation/analytics_screen.dart';
import '../../features/premium/presentation/premium_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/dashboard',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/today',
                builder: (context, state) => const TodayScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/goals',
                builder: (context, state) => const GoalsScreen(),
                routes: [
                  GoRoute(
                    path: ':goalId',
                    // tryParse: a malformed deep link ("/goals/abc") must
                    // not crash the route build. id 0 never matches a
                    // goal, so the detail screen pops back gracefully.
                    builder: (context, state) => GoalDetailScreen(
                      goalId:
                          int.tryParse(state.pathParameters['goalId']!) ?? 0,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/schedule',
                builder: (context, state) => const ScheduleScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/analytics',
                builder: (context, state) => const AnalyticsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/premium',
        builder: (context, state) => const PremiumScreen(),
      ),
      GoRoute(
        path: '/focus/:goalId',
        builder: (context, state) => FocusScreen(
          goalId: int.tryParse(state.pathParameters['goalId']!) ?? 0,
        ),
      ),
    ],
  );
});
