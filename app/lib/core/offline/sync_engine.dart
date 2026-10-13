import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';

import '../platform/file_support.dart';

import '../errors/app_error.dart';
import '../network/supabase_client.dart';
import 'drift_database.dart';
import 'sync_state.dart';

/// Sync Engine — the heart of offline-first.
///
/// Rules (from SYNC-DESIGN.md):
/// - Every local write enqueues a SyncOperation before touching Drift
/// - Server is source of truth for financial records
/// - Client wins on notes and voice (audio always kept)
/// - Money conflicts are surfaced visibly, never silently resolved
/// - Idempotency key prevents duplicate writes on retry
/// - Attachments (photos/audio) use a separate upload queue
/// - Exponential backoff: 1s, 2s, 4s, 8s, 16s (max 5 retries → failed)
class SyncEngine {
  final MunshiLocalDb _db;
  final SupabaseClient _supabase;
  final SyncStateNotifier _stateNotifier;

  Timer? _processTimer;
  StreamSubscription? _connectivitySub;
  bool _processing = false;

  SyncEngine({
    required MunshiLocalDb db,
    required SupabaseClient supabase,
    required SyncStateNotifier stateNotifier,
  })  : _db = db,
        _supabase = supabase,
        _stateNotifier = stateNotifier;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void start() {
    // Process queue every 30 seconds
    _processTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => processQueue(),
    );

    // Also process when connectivity returns
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);
      if (hasNetwork) processQueue();
    });

    // Initial process
    processQueue();
  }

  void stop() {
    _processTimer?.cancel();
    _connectivitySub?.cancel();
  }

  // ── Enqueue ───────────────────────────────────────────────────────────────

  /// Enqueue a sync operation. Call this before EVERY local Drift write.
  Future<String> enqueue({
    required String operationType,
    required String tableName,
    String? rowId,
    required Map<String, dynamic> payload,
    String? attachmentPath,
    String? idempotencyKey,
  }) async {
    final opId = const Uuid().v4();
    final iKey = idempotencyKey ?? const Uuid().v4();

    await _db.into(_db.syncOperations).insert(SyncOperationsCompanion(
      id: Value(opId),
      idempotencyKey: Value(iKey),
      operationType: Value(operationType),
      targetTable: Value(tableName),
      rowId: Value(rowId),
      payload: Value(jsonEncode(payload)),
      attachmentPath: Value(attachmentPath),
      status: const Value('queued'),
    ));

    _stateNotifier.setState(SyncStatus.syncing);
    return opId;
  }

  // ── Process queue ─────────────────────────────────────────────────────────

  Future<void> processQueue() async {
    if (_processing) return;

    // Check connectivity
    final connectivity = await Connectivity().checkConnectivity();
    final hasNetwork = connectivity.any((r) => r != ConnectivityResult.none);
    if (!hasNetwork) return;

    _processing = true;
    try {
      // Get queued + failed-but-retryable operations
      final ops = await (_db.select(_db.syncOperations)
            ..where((t) =>
                t.status.equals('queued') |
                (t.status.equals('failed') & t.retryCount.isSmallerThanValue(5)))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
            ..limit(20))
          .get();

      if (ops.isEmpty) {
        _stateNotifier.setState(SyncStatus.synced);
        return;
      }

      _stateNotifier.setState(SyncStatus.syncing);
      int successCount = 0;
      int failCount = 0;

      for (final op in ops) {
        final success = await _processOperation(op);
        if (success) {
          successCount++;
        } else {
          failCount++;
        }
      }

      if (failCount > 0) {
        _stateNotifier.setState(SyncStatus.failed);
      } else if (successCount > 0) {
        _stateNotifier.setState(SyncStatus.synced);
      }
    } catch (e) {
      debugPrint('SyncEngine.processQueue error: $e');
      _stateNotifier.setState(SyncStatus.failed);
    } finally {
      _processing = false;
    }
  }

  // ── Single operation ──────────────────────────────────────────────────────

  Future<bool> _processOperation(SyncOperation op) async {
    try {
      await _markStatus(op.id, 'uploading');

      switch (op.operationType) {
        case 'insert':
          await _processInsert(op);
        case 'update':
          await _processUpdate(op);
        case 'delete':
          await _processDelete(op);
        case 'upload':
          await _processUpload(op);
        default:
          debugPrint('Unknown operation type: ${op.operationType}');
      }

      await _markStatus(op.id, 'synced', syncedAt: DateTime.now());
      return true;
    } on AppError catch (e) {
      if (e is FinancialIntegrityError) {
        // Financial errors are fatal — don't retry
        await _markStatus(op.id, 'conflict', error: e.message);
        _stateNotifier.addConflict(op.id, e.message);
        return false;
      }
      await _incrementRetry(op.id, e.message);
      return false;
    } catch (e) {
      await _incrementRetry(op.id, e.toString());
      return false;
    }
  }

  Future<void> _processInsert(SyncOperation op) async {
    final payload = jsonDecode(op.payload) as Map<String, dynamic>;
    payload['idempotency_key'] = op.idempotencyKey;

    try {
      await _supabase.from(op.targetTable).insert(payload);
    } on PostgrestException catch (e) {
      // Unique constraint on idempotency_key = already inserted (duplicate submission)
      if (e.code == '23505') {
        debugPrint('Idempotency: ${op.targetTable}/${op.idempotencyKey} already exists');
        return; // Not an error — treat as success
      }
      rethrow;
    }
  }

  Future<void> _processUpdate(SyncOperation op) async {
    if (op.rowId == null) return;
    final payload = jsonDecode(op.payload) as Map<String, dynamic>;
    payload.remove('idempotency_key'); // Updates don't need this

    // Financial tables cannot be updated
    const financialTables = {'payments', 'deal_events', 'audit_log'};
    if (financialTables.contains(op.targetTable)) {
      throw const FinancialIntegrityError('Financial records cannot be updated');
    }

    await _supabase.from(op.targetTable).update(payload).eq('id', op.rowId!);
  }

  Future<void> _processDelete(SyncOperation op) async {
    if (op.rowId == null) return;
    // All deletes are soft-deletes (set deleted_at)
    await _supabase.from(op.targetTable).update({
      'deleted_at': DateTime.now().toIso8601String(),
    }).eq('id', op.rowId!);
  }

  Future<void> _processUpload(SyncOperation op) async {
    // File uploads are not supported on web
    if (kIsWeb) return;

    final localPath = op.attachmentPath;
    if (localPath == null) return;

    final payload = jsonDecode(op.payload) as Map<String, dynamic>;
    final bucket = payload['bucket'] as String;
    final storagePath = payload['storage_path'] as String;
    final refTable = payload['ref_table'] as String?;
    final refId = payload['ref_id'] as String?;
    final fieldName = payload['field_name'] as String?;

    final file = File(localPath);
    if (!await file.exists()) return;

    await _supabase.storage.from(bucket).upload(storagePath, file);

    final url = _supabase.storage.from(bucket).getPublicUrl(storagePath);

    // Update the referring record with the remote URL
    if (refTable != null && refId != null && fieldName != null) {
      await _supabase.from(refTable).update({
        fieldName: url,
      }).eq('id', refId);
    }

    // Update local voice_notes cache
    if (refTable == 'voice_notes') {
      await (_db.update(_db.cachedVoiceNotes)
            ..where((t) => t.id.equals(refId!)))
          .write(CachedVoiceNotesCompanion(
            remoteUrl: Value(url),
            syncStatus: const Value('synced'),
          ));
    }
  }

  // ── DB helpers ────────────────────────────────────────────────────────────

  Future<void> _markStatus(
    String opId,
    String status, {
    DateTime? syncedAt,
    String? error,
  }) async {
    await (_db.update(_db.syncOperations)..where((t) => t.id.equals(opId)))
        .write(SyncOperationsCompanion(
      status: Value(status),
      syncedAt: Value(syncedAt),
      lastError: Value(error),
    ));
  }

  Future<void> _incrementRetry(String opId, String error) async {
    final op = await (_db.select(_db.syncOperations)
          ..where((t) => t.id.equals(opId)))
        .getSingleOrNull();
    if (op == null) return;

    final newRetryCount = op.retryCount + 1;
    final newStatus = newRetryCount >= 5 ? 'failed' : 'queued';

    await (_db.update(_db.syncOperations)..where((t) => t.id.equals(opId)))
        .write(SyncOperationsCompanion(
      retryCount: Value(newRetryCount),
      status: Value(newStatus),
      lastError: Value(error),
    ));

    if (newStatus == 'failed') {
      _stateNotifier.addFailure(opId, error);
    }
  }

  // ── Pull from server ──────────────────────────────────────────────────────

  /// Full bootstrap: pull all data for a dealer on first install.
  Future<void> bootstrapDealer(String dealerId) async {
    _stateNotifier.setState(SyncStatus.syncing);
    try {
      await Future.wait([
        _pullDeals(dealerId),
        _pullParties(dealerId),
        _pullProperties(dealerId),
        _pullFollowups(dealerId),
        _pullPayments(dealerId),
      ]);
      _stateNotifier.setState(SyncStatus.synced);
    } catch (e) {
      debugPrint('Bootstrap failed: $e');
      _stateNotifier.setState(SyncStatus.failed);
    }
  }

  Future<void> _pullDeals(String dealerId) async {
    final data = await _supabase
        .from('deals')
        .select()
        .eq('dealer_id', dealerId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false)
        .limit(100);

    await _db.batch((batch) {
      for (final m in data as List) {
        batch.insert(
          _db.cachedDeals,
          CachedDealsCompanion(
            id: Value(m['id'] as String),
            dealerId: Value(m['dealer_id'] as String),
            stage: Value(m['stage'] as String? ?? 'inquiry'),
            propertyId: Value(m['property_id'] as String?),
            buyerPartyId: Value(m['buyer_party_id'] as String?),
            sellerPartyId: Value(m['seller_party_id'] as String?),
            dealPriceRs: Value(m['deal_price_rs'] as int?),
            commBuyerPct: Value((m['comm_buyer_pct'] as num?)?.toDouble() ?? 1.0),
            commSellerPct: Value((m['comm_seller_pct'] as num?)?.toDouble() ?? 1.0),
            expectedCommRs: Value(m['expected_comm_rs'] as int?),
            tokenType: Value(m['token_type'] as String?),
            tokenRs: Value(m['token_rs'] as int?),
            tokenExpiresAt: Value(m['token_expires_at'] as String?),
            bayanaRs: Value(m['bayana_rs'] as int?),
            notesText: Value(m['notes_text'] as String?),
            createdAt: Value(m['created_at'] as String),
            syncStatus: const Value('synced'),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  Future<void> _pullParties(String dealerId) async {
    final data = await _supabase
        .from('parties')
        .select('id, dealer_id, type, name, name_audio_url, phone, photo_url, source, wa_opt_in, notes_text, created_at')
        .eq('dealer_id', dealerId)
        .isFilter('deleted_at', null)
        .limit(500);

    await _db.batch((batch) {
      for (final m in data as List) {
        batch.insert(
          _db.cachedParties,
          CachedPartiesCompanion(
            id: Value(m['id'] as String),
            dealerId: Value(m['dealer_id'] as String),
            type: Value(m['type'] as String? ?? 'buyer'),
            name: Value(m['name'] as String? ?? ''),
            nameAudioUrl: Value(m['name_audio_url'] as String?),
            phone: Value(m['phone'] as String?),
            photoUrl: Value(m['photo_url'] as String?),
            source: Value(m['source'] as String?),
            waOptIn: Value(m['wa_opt_in'] as bool? ?? false),
            notesText: Value(m['notes_text'] as String?),
            createdAt: Value(m['created_at'] as String),
            syncStatus: const Value('synced'),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  Future<void> _pullProperties(String dealerId) async {
    final data = await _supabase
        .from('properties')
        .select('id, dealer_id, kind, society, block, size_marla, size_label, demand_rs, status, created_at')
        .eq('dealer_id', dealerId)
        .isFilter('deleted_at', null)
        .limit(200);

    await _db.batch((batch) {
      for (final m in data as List) {
        batch.insert(
          _db.cachedProperties,
          CachedPropertiesCompanion(
            id: Value(m['id'] as String),
            dealerId: Value(m['dealer_id'] as String),
            kind: Value(m['kind'] as String? ?? 'plot'),
            society: Value(m['society'] as String? ?? ''),
            block: Value(m['block'] as String?),
            sizeMarla: Value((m['size_marla'] as num?)?.toDouble()),
            sizeLabel: Value(m['size_label'] as String?),
            demandRs: Value(m['demand_rs'] as int?),
            status: Value(m['status'] as String? ?? 'available'),
            createdAt: Value(m['created_at'] as String),
            syncStatus: const Value('synced'),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  Future<void> _pullFollowups(String dealerId) async {
    final data = await _supabase
        .from('followups')
        .select('id, dealer_id, deal_id, party_id, kind, due_at, status, note_text, created_at')
        .eq('dealer_id', dealerId)
        .eq('status', 'pending')
        .limit(100);

    await _db.batch((batch) {
      for (final m in data as List) {
        batch.insert(
          _db.cachedFollowups,
          CachedFollowupsCompanion(
            id: Value(m['id'] as String),
            dealerId: Value(m['dealer_id'] as String),
            dealId: Value(m['deal_id'] as String?),
            partyId: Value(m['party_id'] as String?),
            kind: Value(m['kind'] as String? ?? 'call'),
            dueAt: Value(m['due_at'] as String),
            status: Value(m['status'] as String? ?? 'pending'),
            noteText: Value(m['note_text'] as String?),
            createdAt: Value(m['created_at'] as String),
            syncStatus: const Value('synced'),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  Future<void> _pullPayments(String dealerId) async {
    final now = DateTime.now();
    final threeMonthsAgo = now.subtract(const Duration(days: 90));

    final data = await _supabase
        .from('payments')
        .select('id, dealer_id, deal_id, kind, amount_rs, direction, method, receipt_no, note_text, occurred_at, idempotency_key')
        .eq('dealer_id', dealerId)
        .gte('occurred_at', threeMonthsAgo.toIso8601String())
        .limit(200);

    await _db.batch((batch) {
      for (final m in data as List) {
        batch.insert(
          _db.cachedPayments,
          CachedPaymentsCompanion(
            id: Value(m['id'] as String),
            dealerId: Value(m['dealer_id'] as String),
            dealId: Value(m['deal_id'] as String?),
            kind: Value(m['kind'] as String? ?? 'other_in'),
            amountRs: Value(m['amount_rs'] as int? ?? 0),
            direction: Value(m['direction'] as String? ?? 'in'),
            method: Value(m['method'] as String?),
            receiptNo: Value(m['receipt_no'] as String?),
            noteText: Value(m['note_text'] as String?),
            occurredAt: Value(m['occurred_at'] as String),
            idempotencyKey: Value(m['idempotency_key'] as String? ?? const Uuid().v4()),
            syncStatus: const Value('synced'),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }
}

// Avoid dart:io import at top level — inline it where needed
