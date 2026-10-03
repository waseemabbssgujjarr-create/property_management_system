import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sync status enum shown in the UI indicator.
enum SyncStatus { idle, syncing, synced, failed }

/// Sync state — visible to the entire app.
class SyncState {
  final SyncStatus status;
  final List<SyncConflict> conflicts;
  final List<SyncFailure> failures;
  final DateTime? lastSyncedAt;

  const SyncState({
    this.status = SyncStatus.idle,
    this.conflicts = const [],
    this.failures = const [],
    this.lastSyncedAt,
  });

  SyncState copyWith({
    SyncStatus? status,
    List<SyncConflict>? conflicts,
    List<SyncFailure>? failures,
    DateTime? lastSyncedAt,
  }) => SyncState(
    status: status ?? this.status,
    conflicts: conflicts ?? this.conflicts,
    failures: failures ?? this.failures,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
  );

  bool get hasIssues => conflicts.isNotEmpty || failures.isNotEmpty;
  int get pendingCount => failures.length + conflicts.length;
}

class SyncConflict {
  final String operationId;
  final String message;
  final DateTime occurredAt;
  const SyncConflict({
    required this.operationId,
    required this.message,
    required this.occurredAt,
  });
}

class SyncFailure {
  final String operationId;
  final String error;
  final DateTime occurredAt;
  const SyncFailure({
    required this.operationId,
    required this.error,
    required this.occurredAt,
  });
}

class SyncStateNotifier extends Notifier<SyncState> {
  @override
  SyncState build() => const SyncState();

  void setState(SyncStatus status) {
    state = state.copyWith(
      status: status,
      lastSyncedAt: status == SyncStatus.synced ? DateTime.now() : state.lastSyncedAt,
    );
  }

  void addConflict(String opId, String message) {
    final conflicts = [
      ...state.conflicts,
      SyncConflict(
        operationId: opId,
        message: message,
        occurredAt: DateTime.now(),
      ),
    ];
    state = state.copyWith(status: SyncStatus.failed, conflicts: conflicts);
  }

  void addFailure(String opId, String error) {
    final failures = [
      ...state.failures,
      SyncFailure(
        operationId: opId,
        error: error,
        occurredAt: DateTime.now(),
      ),
    ];
    state = state.copyWith(status: SyncStatus.failed, failures: failures);
  }

  void clearResolved() {
    state = state.copyWith(conflicts: [], failures: []);
    if (state.status == SyncStatus.failed) {
      setState(SyncStatus.idle);
    }
  }
}

final syncStateProvider = NotifierProvider<SyncStateNotifier, SyncState>(
  SyncStateNotifier.new,
);
