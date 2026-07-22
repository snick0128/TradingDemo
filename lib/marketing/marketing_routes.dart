import 'package:go_router/go_router.dart';

import 'pages/about_page.dart';
import 'pages/contact_page.dart';
import 'pages/courses_page.dart';
import 'pages/faq_page.dart';
import 'pages/features_page.dart';
import 'pages/home_page.dart';
import 'pages/legal/legal_page.dart';
import 'pages/pricing_page.dart';

/// Public marketing site routes — top-level (not under /app/ or /admin/) so
/// the auth-guard redirect logic in app_router.dart leaves them untouched.
final List<GoRoute> marketingRoutes = [
  GoRoute(path: '/', builder: (context, state) => const HomePage()),
  GoRoute(path: '/features', builder: (context, state) => const FeaturesPage()),
  GoRoute(path: '/courses', builder: (context, state) => const CoursesPage()),
  GoRoute(path: '/pricing', builder: (context, state) => const PricingPage()),
  GoRoute(path: '/about', builder: (context, state) => const AboutPage()),
  GoRoute(path: '/faq', builder: (context, state) => const FaqPage()),
  GoRoute(path: '/contact', builder: (context, state) => const ContactPage()),
  GoRoute(
    path: '/legal/:slug',
    builder: (context, state) => LegalPage(slug: state.pathParameters['slug']!),
  ),
];
