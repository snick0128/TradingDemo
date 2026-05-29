import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/app_scope.dart';
import '../../domain/auth/auth_session.dart';
import '../../theme.dart';

/// Routing-only splash — shown briefly while the auth session resolves.
///
/// The web/index.html already shows the branded loading screen while Flutter
/// initialises (JS download + engine boot). Showing a second Flutter splash
/// after that creates an unacceptable double-splash experience.
///
/// Solution: this screen is invisible (same background as the web splash so
/// the transition is seamless) and navigates to /app/login as soon as the
/// [AuthSession] finishes loading. GoRouter's redirect then sends already-
/// authenticated users straight to /app/dashboard automatically.
///
/// Max safety fallback: navigate after 3 seconds in case the auth listener
/// never fires (network offline scenario).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  AuthSession? _session;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_session != null) return; // only bind once

    // Try to get AuthSession from AppScope if Firebase is configured.
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    if (scope?.notifier != null) {
      _session = scope!.notifier;
      if (!_session!.isLoading) {
        // Auth already resolved (e.g. fast page reload with cached session).
        WidgetsBinding.instance.addPostFrameCallback((_) => _navigate());
      } else {
        _session!.addListener(_onAuthResolved);
      }
    } else {
      // Firebase not configured — navigate after one frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => _navigate());
    }

    // Safety fallback: navigate after 3 s even if auth never resolves
    // (e.g. offline, Firestore unreachable on first open).
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _navigate();
    });
  }

  void _onAuthResolved() {
    if (_session == null || _session!.isLoading) return;
    _session!.removeListener(_onAuthResolved);
    if (mounted) _navigate();
  }

  void _navigate() {
    if (!mounted) return;
    context.go('/app/login');
  }

  @override
  void dispose() {
    _session?.removeListener(_onAuthResolved);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Transparent scaffold — background matches the web HTML splash (#FAFAFA)
    // so the transition from web splash → Flutter is seamless (no flash).
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: SizedBox.expand(),
    );
  }
}
