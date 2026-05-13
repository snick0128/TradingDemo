import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../domain/auth/auth_session.dart';
import '../presentation/auth/user_login_page.dart';
import '../presentation/auth/admin_login_page.dart';
import '../presentation/app/app_orders_page.dart';
import '../presentation/app/app_portfolio_page.dart';
import '../screens/admin/admin_shell.dart';
import '../screens/main_shell.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/pin_setup_screen.dart';

/// Creates the app-wide GoRouter with dual entry points and role-based guards.
///
/// Entry points:
///   /app/*   → Customer app  (requires role = "user")
///   /admin/* → Admin panel   (requires role = "admin")
///
/// Route guard logic:
///   - Unauthenticated /app/*   → /app/login
///   - Unauthenticated /admin/* → /admin/login
///   - role=admin on /app/*     → /app/login
///   - role=user  on /admin/*   → /admin/login
///   - Already-authenticated user on login page → redirect to dashboard
GoRouter createAppRouter(AuthSession authSession) {
  // ── Multi-URL Detection ─────────────────────────────────────────────
  // This allows hosting the same app on two different domains:
  // e.g. trade-kosh.web.app (Customer) and admin.trade-kosh.web.app (Admin)
  final String host = Uri.base.host;
  final String currentPath = Uri.base.path;
  final String query = Uri.base.query;

  // Define what constitutes an "Admin URL"
  // Matches: admin.trade-kosh.web.app, admin-trade-kosh.web.app, localhost with /admin path
  final bool isAdminHost =
      host.contains('admin') ||
      host.startsWith('admin.') ||
      host.startsWith('admin-') ||
      currentPath.startsWith('/admin');

  // Set the default landing page based on the host
  String defaultLoc = isAdminHost ? '/admin/login' : '/app/login';

  final String initialLoc = (currentPath == '/' || currentPath.isEmpty)
      ? defaultLoc
      : (query.isEmpty ? currentPath : '$currentPath?$query');

  return GoRouter(
    initialLocation: initialLoc,
    refreshListenable: authSession,
    redirect: (BuildContext context, GoRouterState state) {
      if (authSession.isLoading) return null;

      final loc = state.matchedLocation;
      final isAuthenticated = authSession.isAuthenticated;
      final isAdmin = authSession.isAdmin;
      final isUser = authSession.isUser;

      // ── Host-based Enforcement ──────────────────────────────────────
      // If user is on an Admin URL, don't let them access /app/* routes
      if (isAdminHost && loc.startsWith('/app/')) {
        return '/admin/login';
      }
      // If user is on a Customer URL, don't let them access /admin/* routes
      if (!isAdminHost && loc.startsWith('/admin/')) {
        return '/app/login';
      }

      final isAppLogin = loc == '/app/login';
      final isAppRegister = loc == '/app/register';
      final isAdminLogin = loc == '/admin/login';
      final isProtectedApp =
          loc.startsWith('/app/') && !isAppLogin && !isAppRegister;
      final isProtectedAdmin = loc.startsWith('/admin/') && !isAdminLogin;

      // Protect /app/* routes
      if (isProtectedApp) {
        if (!isAuthenticated) return '/app/login';
        if (!isUser) return '/app/login';
      }

      // Protect /admin/* routes
      if (isProtectedAdmin) {
        if (!isAuthenticated) return '/admin/login';
        if (!isAdmin) return '/admin/login';
      }

      // Redirect authenticated users away from login pages
      if (isAppLogin && isAuthenticated && isUser) return '/app/dashboard';
      if (isAdminLogin && isAuthenticated && isAdmin) return '/admin/dashboard';

      return null;
    },
    routes: [
      // ── Customer App ──────────────────────────────────────────────────
      GoRoute(
        path: '/app/login',
        builder: (context, state) => const UserLoginPage(),
      ),
      GoRoute(
        path: '/app/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/app/pin-setup',
        builder: (context, state) => const PinSetupScreen(),
      ),
      GoRoute(
        path: '/app/dashboard',
        builder: (context, state) =>
            MainShell(onThemeToggle: ThemeControllerRef.of(context)),
      ),
      GoRoute(
        path: '/app/orders',
        builder: (context, state) => const AppOrdersPage(),
      ),
      GoRoute(
        path: '/app/portfolio',
        builder: (context, state) => const AppPortfolioPage(),
      ),
      // Full trading shell (existing screens) accessible from /app/shell
      GoRoute(
        path: '/app/shell',
        builder: (context, state) => MainShell(
          onThemeToggle: () {}, // Theme toggle handled by root app
        ),
      ),

      // ── Admin Panel ───────────────────────────────────────────────────
      GoRoute(
        path: '/admin/login',
        builder: (context, state) => const AdminLoginPage(),
      ),
      GoRoute(
        path: '/admin/dashboard',
        builder: (context, state) => const AdminShell(),
      ),
      GoRoute(
        path: '/admin/users',
        builder: (context, state) => const AdminShell(),
      ),
      GoRoute(
        path: '/admin/orders',
        builder: (context, state) => const AdminShell(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text('Page not found: ${state.uri}'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => context.go('/app/login'),
              child: const Text('Go to Login'),
            ),
          ],
        ),
      ),
    ),
  );
}
