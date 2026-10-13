import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:munshi/core/offline/sync_state.dart';

/// SyncStateNotifier tests.
///
/// The notifier is tested via a ProviderContainer so we don't call
/// Notifier-internal methods directly (Notifier.state / Notifier.build()
/// are framework-internal in Riverpod 2.x).
void main() {
  group('SyncState value object', () {
    const idle = SyncState();

    test('initial state is idle', () {
      expect(idle.status, equals(SyncStatus.idle));
      expect(idle.conflicts, isEmpty);
      expect(idle.failures, isEmpty);
      expect(idle.lastSyncedAt, isNull);
      expect(idle.hasIssues, isFalse);
    });

    test('copyWith updates status', () {
      final syncing = idle.copyWith(status: SyncStatus.syncing);
      expect(syncing.status, equals(SyncStatus.syncing));
      expect(syncing.conflicts, isEmpty);
    });

    test('hasIssues is true when conflicts present', () {
      final withConflict = idle.copyWith(conflicts: [
        SyncConflict(
          operationId: 'op-1',
          message: 'test',
          occurredAt: DateTime.now(),
        ),
      ]);
      expect(withConflict.hasIssues, isTrue);
    });

    test('hasIssues is true when failures present', () {
      final withFailure = idle.copyWith(failures: [
        SyncFailure(
          operationId: 'op-1',
          error: 'Network timeout',
          occurredAt: DateTime.now(),
        ),
      ]);
      expect(withFailure.hasIssues, isTrue);
    });

    test('lastSyncedAt is set on synced copyWith', () {
      final now = DateTime.now();
      final synced = idle.copyWith(
        status: SyncStatus.synced,
        lastSyncedAt: now,
      );
      expect(synced.lastSyncedAt, equals(now));
    });
  });

  group('SyncStateNotifier via ProviderContainer', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial provider state is idle', () {
      final state = container.read(syncStateProvider);
      expect(state.status, equals(SyncStatus.idle));
      expect(state.conflicts, isEmpty);
      expect(state.failures, isEmpty);
    });

    test('setState transitions to syncing', () {
      container.read(syncStateProvider.notifier).setState(SyncStatus.syncing);
      expect(
        container.read(syncStateProvider).status,
        equals(SyncStatus.syncing),
      );
    });

    test('setState to synced records lastSyncedAt', () {
      expect(container.read(syncStateProvider).lastSyncedAt, isNull);
      container.read(syncStateProvider.notifier).setState(SyncStatus.synced);
      expect(container.read(syncStateProvider).lastSyncedAt, isNotNull);
    });

    test('addConflict sets failed status and stores conflict', () {
      container.read(syncStateProvider.notifier).addConflict(
            'op-1',
            'Split sum != 100%',
          );
      final state = container.read(syncStateProvider);
      expect(state.status, equals(SyncStatus.failed));
      expect(state.conflicts, hasLength(1));
      expect(state.conflicts.first.operationId, equals('op-1'));
      expect(state.conflicts.first.message, contains('100'));
    });

    test('addFailure stores failure and sets failed status', () {
      container.read(syncStateProvider.notifier).addFailure(
            'op-2',
            'Network timeout',
          );
      final state = container.read(syncStateProvider);
      expect(state.failures, hasLength(1));
      expect(state.failures.first.error, contains('Network'));
      expect(state.hasIssues, isTrue);
    });

    test('clearResolved empties conflicts and failures', () {
      final notifier = container.read(syncStateProvider.notifier);
      notifier.addConflict('op-1', 'test conflict');
      notifier.addFailure('op-2', 'test failure');

      notifier.clearResolved();

      final state = container.read(syncStateProvider);
      expect(state.conflicts, isEmpty);
      expect(state.failures, isEmpty);
    });

    test('multiple conflicts accumulate', () {
      final notifier = container.read(syncStateProvider.notifier);
      notifier.addConflict('op-1', 'conflict 1');
      notifier.addConflict('op-2', 'conflict 2');
      expect(container.read(syncStateProvider).conflicts, hasLength(2));
    });
  });
}
