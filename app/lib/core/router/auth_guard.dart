import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/session_provider.dart';
import 'app_router.dart';

/// Route guards using GoRouter redirect.
/// Plugged into the GoRouter redirect callback.

String? authRedirect(WidgetRef ref, GoRouterState state) {
  final session = ref.read(currentSessionProvider);
  final isLoading = ref.read(sessionProvider).isLoading;

  // During loading: stay on current route
  if (isLoading) return null;

  final isAuthenticated = session != null;
  final loc = state.uri.path;

  // Unauthenticated routes
  final publicRoutes = [AppRoutes.splash, AppRoutes.otp, AppRoutes.onboarding];
  final isPublic = publicRoutes.any((r) => loc.startsWith(r));

  if (!isAuthenticated && !isPublic) {
    return '${AppRoutes.otp}?phone=';
  }

  if (isAuthenticated && (loc == AppRoutes.otp || loc == AppRoutes.splash)) {
    return AppRoutes.home;
  }

  return null;
}
