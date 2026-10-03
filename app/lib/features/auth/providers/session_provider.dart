import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/supabase_client.dart';
import '../models/auth_models.dart';
import '../repositories/auth_repository.dart';

/// Current app session — the single source of truth for auth state.
/// null = not authenticated.
class SessionNotifier extends AsyncNotifier<AppSession?> {
  @override
  Future<AppSession?> build() async {
    // Watch auth state changes (login/logout)
    ref.listen(authStateProvider, (_, next) {
      next.whenData((_) => ref.invalidateSelf());
    });
    return ref.read(authRepositoryProvider).loadSession();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const AsyncData(null);
  }
}

final sessionProvider = AsyncNotifierProvider<SessionNotifier, AppSession?>(
  SessionNotifier.new,
);

/// Convenience sync accessor — null-safe
final currentSessionProvider = Provider<AppSession?>((ref) {
  return ref.watch(sessionProvider).valueOrNull;
});

/// Whether the user is authenticated
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(currentSessionProvider) != null;
});
