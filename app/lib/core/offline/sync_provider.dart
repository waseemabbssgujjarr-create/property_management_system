import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/supabase_client.dart';
import 'drift_database.dart';
import 'sync_engine.dart';
import 'sync_state.dart';

/// SyncEngine provider — singleton for the app lifetime.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(
    db: ref.watch(localDbProvider),
    supabase: ref.watch(supabaseClientProvider),
    stateNotifier: ref.watch(syncStateProvider.notifier),
  );
  engine.start();
  ref.onDispose(engine.stop);
  return engine;
});
