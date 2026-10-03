import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/auth/screens/onboarding_screen.dart';
import '../../shell/main_shell.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/deals/screens/deals_screen.dart';
import '../../features/deals/screens/deal_detail_screen.dart';
import '../../features/deals/screens/naya_deal_screen.dart';
import '../../features/inventory/screens/inventory_screen.dart';
import '../../features/inventory/screens/property_detail_screen.dart';
import '../../features/parties/screens/parties_screen.dart';
import '../../features/parties/screens/party_detail_screen.dart';
import '../../features/money/screens/paisa_aya_screen.dart';
import '../../features/money/screens/paisa_gaya_screen.dart';
import '../../features/money/screens/receipts_screen.dart';
import '../../features/staff/screens/staff_screen.dart';
import '../../features/staff/screens/staff_detail_screen.dart';
import '../../features/followups/screens/followups_screen.dart';
import '../../features/search/screens/search_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/documents/screens/documents_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/billing/screens/subscription_screen.dart';
import '../../features/import/screens/import_screen.dart';
import '../../features/reports/screens/reports_screen.dart';
import '../../features/whatsapp/screens/wa_connect_screen.dart';

/// Named routes — single source of truth for all route paths.
abstract final class AppRoutes {
  static const splash         = '/';
  static const otp            = '/otp';
  static const onboarding     = '/onboarding';
  static const home           = '/home';
  static const deals          = '/deals';
  static const dealDetail     = '/deals/:id';
  static const nayaDeal       = '/deals/new';
  static const paisaAya       = '/paisa-aya';
  static const paisaGaya      = '/paisa-gaya';
  static const inventory      = '/inventory';
  static const propertyDetail = '/inventory/:id';
  static const parties        = '/parties';
  static const partyDetail    = '/parties/:id';
  static const staff          = '/staff';
  static const staffDetail    = '/staff/:id';
  static const followups      = '/followups';
  static const search         = '/search';
  static const notifications  = '/notifications';
  static const documents      = '/documents';
  static const receipts       = '/receipts';
  static const settings       = '/settings';
  static const subscription   = '/subscription';
  static const reports        = '/reports';
  static const importData     = '/import';
  static const whatsapp       = '/whatsapp';
}

/// Public routes — accessible without authentication.
const _publicPaths = [AppRoutes.splash, AppRoutes.otp, AppRoutes.onboarding];

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,

    // ── Auth redirect guard ────────────────────────────────────────────
    redirect: (context, state) {
      final loc = state.uri.path;
      final isPublic = _publicPaths.any((p) => loc.startsWith(p));
      final isAuthenticated = Supabase.instance.client.auth.currentUser != null;

      if (!isAuthenticated && !isPublic) {
        return '${AppRoutes.otp}?phone=';
      }
      return null;
    },

    routes: [
      // ── Unauthenticated ────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.otp,
        builder: (_, state) => OtpScreen(
          phone: state.uri.queryParameters['phone'] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (_, __) => const OnboardingScreen(),
      ),

      // ── Authenticated shell ────────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(path: AppRoutes.home,          builder: (_, __) => const HomeScreen()),
          GoRoute(
            path: AppRoutes.deals,
            builder: (_, __) => const DealsScreen(),
            routes: [
              GoRoute(path: 'new', builder: (_, __) => const NayaDealScreen()),
              GoRoute(
                path: ':id',
                builder: (_, s) => DealDetailScreen(dealId: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.inventory,
            builder: (_, __) => const InventoryScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => PropertyDetailScreen(propertyId: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.parties,
            builder: (_, __) => const PartiesScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => PartyDetailScreen(partyId: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(path: AppRoutes.paisaAya,      builder: (_, __) => const PaisaAyaScreen()),
          GoRoute(path: AppRoutes.paisaGaya,      builder: (_, __) => const PaisaGayaScreen()),
          GoRoute(
            path: AppRoutes.staff,
            builder: (_, __) => const StaffScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => StaffDetailScreen(staffId: s.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(path: AppRoutes.followups,     builder: (_, __) => const FollowupsScreen()),
          GoRoute(path: AppRoutes.search,        builder: (_, __) => const SearchScreen()),
          GoRoute(path: AppRoutes.notifications, builder: (_, __) => const NotificationsScreen()),
          GoRoute(path: AppRoutes.documents,     builder: (_, __) => const DocumentsScreen()),
          GoRoute(path: AppRoutes.receipts,      builder: (_, __) => const ReceiptsScreen()),
          GoRoute(path: AppRoutes.settings,      builder: (_, __) => const SettingsScreen()),
          GoRoute(path: AppRoutes.subscription,  builder: (_, __) => const SubscriptionScreen()),
          GoRoute(path: AppRoutes.reports,       builder: (_, __) => const ReportsScreen()),
          GoRoute(path: AppRoutes.importData,    builder: (_, __) => const ImportScreen()),
          GoRoute(path: AppRoutes.whatsapp,      builder: (_, __) => const WaConnectScreen()),
        ],
      ),
    ],

    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('صفحہ نہیں ملا',
            style: Theme.of(context).textTheme.headlineMedium),
      ),
    ),
  );
});
