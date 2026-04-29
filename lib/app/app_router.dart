import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../domain/auth/auth_session.dart';
import '../presentation/auth/user_login_page.dart';
import '../presentation/auth/admin_login_page.dart';
import '../presentation/app/app_orders_page.dart';
import '../presentation/app/app_portfolio_page.dart';
import '../screens/admin/admin_shell.dart';
import '../screens/main_shell.dart';

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
  return GoRouter(
    initialLocation: '/app/login',
    refreshListenable: authSession,
    redirect: (BuildContext context, GoRouterState state) {
      // Wait for auth state to resolve
      if (authSession.isLoading) return null;

      final loc = state.matchedLocation;
      final isAuthenticated = authSession.isAuthenticated;
      final isAdmin = authSession.isAdmin;
      final isUser = authSession.isUser;

      final isAppLogin = loc == '/app/login';
      final isAdminLogin = loc == '/admin/login';
      final isProtectedApp =
          loc.startsWith('/app/') && !isAppLogin;
      final isProtectedAdmin =
          loc.startsWith('/admin/') && !isAdminLogin;

      // Protect /app/* routes
      if (isProtectedApp) {
        if (!isAuthenticated) return '/app/login';
        if (!isUser) return '/app/login'; // admin trying user routes
      }

      // Protect /admin/* routes
      if (isProtectedAdmin) {
        if (!isAuthenticated) return '/admin/login';
        if (!isAdmin) return '/admin/login'; // user trying admin routes
      }

      // Redirect authenticated users away from login pages
      if (isAppLogin && isAuthenticated && isUser) return '/app/dashboard';
      if (isAdminLogin && isAuthenticated && isAdmin) return '/admin/dashboard';

      return null; // allow navigation
    },
    routes: [
      // ── Customer App ──────────────────────────────────────────────────
      GoRoute(
        path: '/app/login',
        builder: (context, state) => const UserLoginPage(),
      ),
      GoRoute(
        path: '/app/dashboard',
        builder: (context, state) => MainShell(
          onThemeToggle: ThemeControllerRef.of(context),
        ),
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
