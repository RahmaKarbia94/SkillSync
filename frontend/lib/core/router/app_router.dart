import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/assessment/presentation/assessment_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/dashboard/presentation/results_screen.dart';
import '../providers/auth_provider.dart';

class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (previous?.status != next.status) {
        notifyListeners();
      }
    });
  }
}

final goRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier(ref);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final isAuthenticated = authState.isAuthenticated;
      final isLoggingIn = state.matchedLocation == '/login';

      if (!isAuthenticated && !isLoggingIn) {
        return '/login';
      }
      if (isAuthenticated && isLoggingIn) {
        return '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/assessment/:sessionId',
        builder: (context, state) => AssessmentScreen(
          sessionId: state.pathParameters['sessionId']!,
        ),
      ),
      GoRoute(
        path: '/results/:sessionId',
        builder: (context, state) => ResultsScreen(
          sessionId: state.pathParameters['sessionId']!,
        ),
      ),
    ],
  );
});