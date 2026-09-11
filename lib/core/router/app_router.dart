import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../services/onboarding.dart';
import '../services/shared_preferences_provider.dart';
import '../router/app_shell.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/today/presentation/today_screen.dart';
import '../../features/goals/presentation/goals_screen.dart';
import '../../features/goals/presentation/goal_detail_screen.dart';
import '../../features/focus/presentation/focus_screen.dart';
import '../../features/schedule/presentation/schedule_screen.dart';
import '../../features/analytics/presentation/analytics_screen.dart';
import '../../features/admin/presentation/admin_screen.dart';
import '../../features/habits/presentation/habits_screen.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/premium/presentation/premium_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);

  return GoRouter(
    initialLocation: '/dashboard',
    redirect: (context, state) {
      if (Onboarding.isComplete(prefs)) return null;
      // /premium stays reachable so "I already have an account" can sign in
      // without being bounced back to the welcome screen.
      const allowed = {'/welcome', '/premium'};
      if (allowed.contains(state.matchedLocation)) return null;
      return '/welcome';
    },
    routes: [
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
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
        path: '/admin',
        builder: (context, state) => const AdminScreen(),
      ),
      GoRoute(
        path: '/habits',
        builder: (context, state) => const HabitsScreen(),
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
