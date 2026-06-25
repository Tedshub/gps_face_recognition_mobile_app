import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/history/history_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/dashboard/presence_guide_screen.dart';

import '../features/auth/auth_notifier.dart';
import '../features/auth/login_screen.dart';
import '../features/onboarding/onboarding_screen.dart';

/// GoRouter konfigurasi dengan ShellRoute untuk bottom tab navigation.
///
/// Routes:
///   /login              -- LoginScreen (standalone)
///   / (ShellRoute)
///     /dashboard        -- DashboardScreen (tab 0)
///     /history          -- HistoryScreen (tab 1)
///     /profile          -- ProfileScreen (tab 2)
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/dashboard',
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final isAuth = authState.status == AuthStatus.authenticated;
      final isUnauth = authState.status == AuthStatus.unauthenticated;
      
      final path = state.uri.path;
      final isGoingToLogin = path == '/login';
      final isGoingToOnboarding = path == '/onboarding';

      if (isUnauth && !isGoingToLogin && !isGoingToOnboarding) {
        return '/onboarding';
      }

      if (isAuth && (isGoingToLogin || isGoingToOnboarding)) {
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
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/history',
            builder: (context, state) => const HistoryScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/presence-guide',
        builder: (context, state) => const PresenceGuideScreen(),
      ),
    ],
  );

  ref.listen(authProvider, (previous, next) {
    if (previous?.status != next.status) {
      if (next.status == AuthStatus.authenticated) {
        router.go('/dashboard');
      } else if (next.status == AuthStatus.unauthenticated) {
        final currentPath = router.routerDelegate.currentConfiguration.uri.path;
        if (currentPath != '/login') {
          router.go('/onboarding');
        }
      }
    }
  });

  return router;
});

/// Shell widget dengan BottomNavigationBar untuk tiga tab.
class MainShell extends StatelessWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  int _getCurrentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/history')) return 1;
    if (location.startsWith('/profile')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _getCurrentIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              context.go('/dashboard');
              break;
            case 1:
              context.go('/history');
              break;
            case 2:
              context.go('/profile');
              break;
          }
        },
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFDCFCE7),
        elevation: 0,
        destinations: [
          NavigationDestination(
            icon: Icon(
              currentIndex == 0 ? Icons.home : Icons.home_outlined,
            ),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(
              currentIndex == 1 ? Icons.history : Icons.history_outlined,
            ),
            label: 'Riwayat Presensi',
          ),
          NavigationDestination(
            icon: Icon(
              currentIndex == 2 ? Icons.person : Icons.person_outlined,
            ),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
