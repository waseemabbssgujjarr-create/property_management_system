// Web stub for offline database.
// On web the drift offline database is a no-op: the web owner console is
// read-heavy and sync operations are all guarded by !kIsWeb checks.
// This stub satisfies the dart:ffi-free build requirement by implementing
// QueryExecutor without importing dart:ffi or package:sqlite3.
import 'package:drift/drift.dart';

QueryExecutor openAppDatabase() => _WebNoopExecutor();

/// No-op executor for web targets. Every method returns an empty result or
/// completes immediately. The SyncEngine never calls these methods on web
/// because all sync paths are guarded with `if (kIsWeb) return`.
class _WebNoopExecutor extends QueryExecutor {
  @override
  Future<bool> ensureOpen(QueryExecutorUser user) async => true;

  @override
  Future<void> close() async {}

  @override
  Future<List<Map<String, Object?>>> runSelect(
          String statement, List<Object?> args) async =>
      const [];

  @override
  Future<int> runInsert(String statement, List<Object?> args) async => 0;

  @override
  Future<int> runUpdate(String statement, List<Object?> args) async => 0;

  @override
  Future<int> runDelete(String statement, List<Object?> args) async => 0;

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) async {}

  @override
  Future<void> runBatched(BatchedStatements statements) async {}

  @override
  TransactionExecutor beginTransaction() => _WebNoopTransaction();

  @override
  QueryExecutor beginExclusive() => _WebNoopExecutor();

  @override
  SqlDialect get dialect => SqlDialect.sqlite;
}

class _WebNoopTransaction extends _WebNoopExecutor
    implements TransactionExecutor {
  @override
  bool get supportsNestedTransactions => false;

  @override
  Future<void> send() async {}

  @override
  Future<void> rollback() async {}
}
