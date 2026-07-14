import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../network/auth_state.dart';
import '../splash/splash_screen.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/onboarding/presentation/instructions_screen.dart';
import '../../features/onboarding/presentation/scan_screen.dart';
import '../../features/onboarding/presentation/staff_login_screen.dart';
import '../../features/inventory/inventory_screen.dart';
import '../../features/pos/app_shell.dart';
import '../../features/pos/pos_screen.dart';
import '../../features/debug/debug_status_screen.dart';

/// Route guard logic:
/// - pairing/session still loading -> /splash
/// - not paired                    -> always /onboarding/welcome
/// - paired, no session            -> /onboarding/login
/// - paired + session              -> the main app shell (POS/Inventory/Settings)
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: _RouterRefresh(ref),
    redirect: (context, state) {
      final pairing = ref.read(pairingStatusProvider);
      final session = ref.read(sessionStatusProvider);
      final current = state.matchedLocation;
<<<<<<< HEAD
      final isDebugRoute = current == '/debug';
      final isScanRoute = current == '/onboarding/scan';

      // Keep diagnostic + pairing scanner routes reachable regardless of
      // pairing/login state, so users can always inspect and re-pair.
      if (isDebugRoute || isScanRoute) {
        return null;
      }
=======
>>>>>>> d647790f179ea85ecb3c54e2a8ea3e8e98c11006

      if (pairing.isLoading || session.isLoading) {
        return current == '/splash' ? null : '/splash';
      }

      final isPaired = pairing.valueOrNull != null;
      final isLoggedIn = session.valueOrNull != null;
      final inOnboarding = current.startsWith('/onboarding');

      if (!isPaired) {
        return inOnboarding && current != '/splash'
            ? null
            : '/onboarding/welcome';
      }

      if (!isLoggedIn) {
        return current == '/onboarding/login' ? null : '/onboarding/login';
      }

      // Paired + logged in: keep out of onboarding/splash.
      if (inOnboarding || current == '/splash') return '/pos';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/onboarding/instructions',
        builder: (context, state) => const InstructionsScreen(),
      ),
      GoRoute(
        path: '/onboarding/scan',
        builder: (context, state) => const ScanScreen(),
      ),
      GoRoute(
        path: '/onboarding/login',
        builder: (context, state) => const StaffLoginScreen(),
      ),
      GoRoute(
        path: '/debug',
        builder: (context, state) => const DebugStatusScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/pos',
              builder: (context, state) => const PosScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/inventory',
              builder: (context, state) => const InventoryScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsTabPlaceholder(),
            ),
          ]),
        ],
      ),
    ],
  );
});

/// Bridges Riverpod stream changes into go_router's `refreshListenable`
/// so pairing/login changes trigger an immediate redirect re-evaluation
/// instead of waiting for the next navigation event.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(pairingStatusProvider, (_, __) => notifyListeners());
    ref.listen(sessionStatusProvider, (_, __) => notifyListeners());
  }
}
