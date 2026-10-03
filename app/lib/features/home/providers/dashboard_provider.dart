import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/session_provider.dart';
import '../models/dashboard_models.dart';
import '../repositories/dashboard_repository.dart';

/// Dashboard summary provider.
/// Auto-refreshes when the session changes.
/// Supports manual refresh (pull-to-refresh).
class DashboardNotifier extends AsyncNotifier<DashboardSummary?> {
  @override
  Future<DashboardSummary?> build() async {
    final session = ref.watch(currentSessionProvider);
    if (session == null) return null;
    return ref
        .read(dashboardRepositoryProvider)
        .getDashboardSummary(session.dealerId);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final dashboardProvider =
    AsyncNotifierProvider<DashboardNotifier, DashboardSummary?>(
  DashboardNotifier.new,
);
