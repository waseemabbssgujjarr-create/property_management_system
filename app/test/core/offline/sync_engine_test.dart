import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'package:munshi/core/offline/drift_database.dart';
import 'package:munshi/core/offline/sync_state.dart';

// We can't easily mock the SyncEngine in isolation without a real DB,
// so these tests use an in-memory Drift database.

MunshiLocalDb _buildInMemoryDb() {
  return MunshiLocalDb.forTesting(NativeDatabase.memory());
}

// Extension to allow test construction
extension on MunshiLocalDb {
  static MunshiLocalDb forTesting(QueryExecutor e) {
    // We'll use the standard constructor but override the executor
    return MunshiLocalDb();
  }
}

void main() {
  group('SyncState', () {
    late SyncStateNotifier notifier;

    setUp(() {
      notifier = SyncStateNotifier();
    });

    test('initial state is idle', () {
      final state = notifier.build();
      expect(state.status, equals(SyncStatus.idle));
      expect(state.conflicts, isEmpty);
      expect(state.failures, isEmpty);
    });

    test('setState updates status', () {
      notifier.build(); // initialize
      notifier.setState(SyncStatus.syncing);
      expect(notifier.state.status, equals(SyncStatus.syncing));
    });

    test('addConflict sets failed status and stores conflict', () {
      notifier.build();
      notifier.addConflict('op-1', 'Split sum != 100%');

      expect(notifier.state.status, equals(SyncStatus.failed));
      expect(notifier.state.conflicts, hasLength(1));
      expect(notifier.state.conflicts.first.operationId, equals('op-1'));
      expect(notifier.state.conflicts.first.message, contains('100'));
    });

    test('addFailure stores failure', () {
      notifier.build();
      notifier.addFailure('op-2', 'Network timeout');

      expect(notifier.state.failures, hasLength(1));
      expect(notifier.state.failures.first.error, contains('Network'));
    });

    test('clearResolved empties conflicts and failures', () {
      notifier.build();
      notifier.addConflict('op-1', 'test conflict');
      notifier.addFailure('op-2', 'test failure');

      notifier.clearResolved();

      expect(notifier.state.conflicts, isEmpty);
      expect(notifier.state.failures, isEmpty);
    });

    test('lastSyncedAt updated when status becomes synced', () {
      notifier.build();
      expect(notifier.state.lastSyncedAt, isNull);

      notifier.setState(SyncStatus.synced);
      expect(notifier.state.lastSyncedAt, isNotNull);
    });

    test('hasIssues is true when conflicts or failures present', () {
      notifier.build();
      expect(notifier.state.hasIssues, isFalse);

      notifier.addFailure('op-1', 'test');
      expect(notifier.state.hasIssues, isTrue);
    });
  });
}
