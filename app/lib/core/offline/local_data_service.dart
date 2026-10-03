import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'drift_database.dart';
import 'sync_engine.dart';
import 'sync_provider.dart';

/// LocalDataService — the offline-first data access layer.
///
/// All local writes:
/// 1. Write to Drift (immediate, works offline)
/// 2. Enqueue a SyncOperation (processed when online)
///
/// All reads come from Drift first (instant), background-refreshed from server.
class LocalDataService {
  final MunshiLocalDb _db;
  final SyncEngine _sync;

  LocalDataService({required MunshiLocalDb db, required SyncEngine sync})
      : _db = db,
        _sync = sync;

  // ── Deals ─────────────────────────────────────────────────────────────────

  Future<List<CachedDeal>> getDealsLocal(String dealerId, {String? stage}) async {
    final query = _db.select(_db.cachedDeals)
      ..where((t) => t.dealerId.equals(dealerId));
    if (stage != null) {
      query.where((t) => t.stage.equals(stage));
    }
    return query.get();
  }

  Future<String> createDealLocal({
    required String dealerId,
    required String createdBy,
    String? propertyId,
    String? buyerPartyId,
    String? sellerPartyId,
    int? dealPriceRs,
    double commBuyerPct = 1.0,
    double commSellerPct = 1.0,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    final idempotencyKey = const Uuid().v4();

    // Write to local Drift DB
    await _db.into(_db.cachedDeals).insert(CachedDealsCompanion(
      id: Value(id),
      dealerId: Value(dealerId),
      stage: const Value('inquiry'),
      propertyId: Value(propertyId),
      buyerPartyId: Value(buyerPartyId),
      sellerPartyId: Value(sellerPartyId),
      dealPriceRs: Value(dealPriceRs),
      commBuyerPct: Value(commBuyerPct),
      commSellerPct: Value(commSellerPct),
      createdAt: Value(now),
      syncStatus: const Value('queued'),
    ));

    // Enqueue for server sync
    await _sync.enqueue(
      operationType: 'insert',
      tableName: 'deals',
      rowId: id,
      payload: {
        'id': id,
        'dealer_id': dealerId,
        'property_id': propertyId,
        'buyer_party_id': buyerPartyId,
        'seller_party_id': sellerPartyId,
        'stage': 'inquiry',
        'deal_price_rs': dealPriceRs,
        'comm_buyer_pct': commBuyerPct,
        'comm_seller_pct': commSellerPct,
        'created_by': createdBy,
        'created_at': now,
      },
      idempotencyKey: idempotencyKey,
    );

    return id;
  }

  // ── Followups ─────────────────────────────────────────────────────────────

  Future<List<CachedFollowup>> getFollowupsLocal(
    String dealerId, {
    bool pendingOnly = true,
  }) async {
    final query = _db.select(_db.cachedFollowups)
      ..where((t) => t.dealerId.equals(dealerId));
    if (pendingOnly) {
      query.where((t) => t.status.equals('pending'));
    }
    query.orderBy([(t) => OrderingTerm.asc(t.dueAt)]);
    return query.get();
  }

  Future<String> createFollowupLocal({
    required String dealerId,
    required String createdBy,
    String? dealId,
    String? partyId,
    required String kind,
    required DateTime dueAt,
    String? noteText,
    String? noteAudioPath,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    final idempotencyKey = const Uuid().v4();

    await _db.into(_db.cachedFollowups).insert(CachedFollowupsCompanion(
      id: Value(id),
      dealerId: Value(dealerId),
      dealId: Value(dealId),
      partyId: Value(partyId),
      kind: Value(kind),
      dueAt: Value(dueAt.toIso8601String()),
      status: const Value('pending'),
      noteText: Value(noteText),
      noteAudioUrl: Value(noteAudioPath),
      createdAt: Value(now),
      syncStatus: const Value('queued'),
    ));

    await _sync.enqueue(
      operationType: 'insert',
      tableName: 'followups',
      rowId: id,
      payload: {
        'id': id,
        'dealer_id': dealerId,
        'deal_id': dealId,
        'party_id': partyId,
        'kind': kind,
        'due_at': dueAt.toIso8601String(),
        'status': 'pending',
        'note_text': noteText,
        'created_by': createdBy,
        'created_at': now,
      },
      idempotencyKey: idempotencyKey,
      attachmentPath: noteAudioPath,
    );

    // If there's an audio note, also queue the upload
    if (noteAudioPath != null) {
      await _sync.enqueue(
        operationType: 'upload',
        tableName: 'voice_notes',
        payload: {
          'bucket': 'voice-notes',
          'storage_path': '$dealerId/followups/$id.m4a',
          'ref_table': 'followups',
          'ref_id': id,
          'field_name': 'note_audio_url',
        },
        attachmentPath: noteAudioPath,
      );
    }

    return id;
  }

  Future<void> markFollowupDoneLocal(String id, String dealerId) async {
    await (_db.update(_db.cachedFollowups)
          ..where((t) => t.id.equals(id)))
        .write(const CachedFollowupsCompanion(
          status: Value('done'),
        ));

    await _sync.enqueue(
      operationType: 'update',
      tableName: 'followups',
      rowId: id,
      payload: {
        'status': 'done',
        'done_at': DateTime.now().toIso8601String(),
      },
    );
  }

  // ── Voice notes ───────────────────────────────────────────────────────────

  /// Store a voice note locally and queue upload to Supabase Storage.
  Future<String> saveVoiceNoteLocal({
    required String dealerId,
    required String refTable,
    required String refId,
    required String localPath,
    String? transcript,
    int? durationSeconds,
  }) async {
    final id = const Uuid().v4();
    final storagePath = '$dealerId/$refTable/$refId/${id}.m4a';

    await _db.into(_db.cachedVoiceNotes).insert(CachedVoiceNotesCompanion(
      id: Value(id),
      dealerId: Value(dealerId),
      refTable: Value(refTable),
      refId: Value(refId),
      localPath: Value(localPath),
      transcriptUr: Value(transcript),
      durationS: Value(durationSeconds),
      createdAt: Value(DateTime.now().toIso8601String()),
      syncStatus: const Value('queued'),
    ));

    // Queue upload
    await _sync.enqueue(
      operationType: 'upload',
      tableName: 'voice_notes',
      rowId: id,
      payload: {
        'bucket': 'voice-notes',
        'storage_path': storagePath,
        'ref_table': 'voice_notes',
        'ref_id': id,
        'field_name': 'audio_url',
        'dealer_id': dealerId,
        'dealer_ref_table': refTable,
        'dealer_ref_id': refId,
        'transcript_ur': transcript,
        'duration_s': durationSeconds,
      },
      attachmentPath: localPath,
    );

    return id;
  }

  // ── Sync status ───────────────────────────────────────────────────────────

  Future<int> getPendingCount() async {
    final result = await (_db.select(_db.syncOperations)
          ..where((t) =>
              t.status.equals('queued') | t.status.equals('uploading')))
        .get();
    return result.length;
  }

  Future<List<SyncOperation>> getFailedOperations() async {
    return (_db.select(_db.syncOperations)
          ..where((t) => t.status.equals('failed'))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<void> retryFailedOperations() async {
    await (_db.update(_db.syncOperations)
          ..where((t) => t.status.equals('failed')))
        .write(const SyncOperationsCompanion(
      status: Value('queued'),
      retryCount: Value(0),
    ));
    await _sync.processQueue();
  }
}

final localDataServiceProvider = Provider<LocalDataService>((ref) {
  return LocalDataService(
    db: ref.watch(localDbProvider),
    sync: ref.watch(syncEngineProvider),
  );
});
