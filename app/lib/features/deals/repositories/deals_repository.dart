import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/network/supabase_client.dart';
import '../models/deal_models.dart';

export '../models/deal_models.dart';

/// Deal state machine: valid forward transitions only.
/// Lost is always allowed from any non-terminal stage.
const _validTransitions = <DealStage, List<DealStage>>{
  DealStage.inquiry:  [DealStage.token,    DealStage.lost],
  DealStage.token:    [DealStage.bayana,   DealStage.lost],
  DealStage.bayana:   [DealStage.registry, DealStage.lost],
  DealStage.registry: [DealStage.closed,   DealStage.lost],
  DealStage.closed:   [],
  DealStage.lost:     [],
};

class DealsRepository {
  final SupabaseClient _client;
  DealsRepository(this._client);

  Future<List<Deal>> getDeals({
    required String dealerId,
    DealStage? filterStage,
    String? filterAgentId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      // Build filter chain first, add order+range last so the type stays
      // PostgrestFilterBuilder throughout the conditional blocks.
      var query = _client
          .from('deals')
          .select()
          .eq('dealer_id', dealerId)
          .isFilter('deleted_at', null);

      if (filterStage != null) {
        query = query.eq('stage', filterStage.dbValue);
      }
      if (filterAgentId != null) {
        query = query.eq('assigned_agent_id', filterAgentId);
      }

      final data = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return (data as List)
          .map((m) => Deal.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<Deal> getDeal(String id, String dealerId) async {
    try {
      final data = await _client
          .from('deals')
          .select()
          .eq('id', id)
          .eq('dealer_id', dealerId)
          .single();
      return Deal.fromMap(data);
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<List<DealEvent>> getDealEvents(String dealId, String dealerId) async {
    try {
      final data = await _client
          .from('deal_events')
          .select()
          .eq('deal_id', dealId)
          .eq('dealer_id', dealerId)
          .order('occurred_at', ascending: true);
      return (data as List)
          .map((m) => DealEvent.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<List<DealSplit>> getDealSplits(String dealId, String dealerId) async {
    try {
      final data = await _client
          .from('deal_splits')
          .select()
          .eq('deal_id', dealId)
          .eq('dealer_id', dealerId)
          .isFilter('deleted_at', null);
      return (data as List)
          .map((m) => DealSplit.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw mapException(e);
    }
  }

  /// Create a new deal and log the inquiry event.
  Future<Deal> createDeal({
    required String dealerId,
    required String? propertyId,
    required String? buyerPartyId,
    String? sellerPartyId,
    String? assignedAgentId,
    int? dealPriceRs,
    double commBuyerPct = 1.0,
    double commSellerPct = 1.0,
    String? createdBy,
  }) async {
    try {
      final data = await _client.from('deals').insert({
        'dealer_id': dealerId,
        'property_id': propertyId,
        'buyer_party_id': buyerPartyId,
        'seller_party_id': sellerPartyId,
        'assigned_agent_id': assignedAgentId,
        'stage': DealStage.inquiry.dbValue,
        'deal_price_rs': dealPriceRs,
        'comm_buyer_pct': commBuyerPct,
        'comm_seller_pct': commSellerPct,
        'created_by': createdBy,
      }).select().single();

      final deal = Deal.fromMap(data);

      // Log creation event
      await _logEvent(
        dealId: deal.id,
        dealerId: dealerId,
        kind: 'created',
        toStage: DealStage.inquiry.dbValue,
        actorId: createdBy,
      );

      return deal;
    } catch (e) {
      throw mapException(e);
    }
  }

  /// Advance stage — enforces the state machine.
  Future<Deal> advanceStage({
    required String dealId,
    required String dealerId,
    required DealStage fromStage,
    required DealStage toStage,
    required String actorId,
    Map<String, dynamic> stageData = const {},
  }) async {
    // Validate transition
    final allowed = _validTransitions[fromStage] ?? [];
    if (!allowed.contains(toStage)) {
      throw FinancialIntegrityError(
        '${fromStage.labelUr} سے ${toStage.labelUr} پر جانا ممکن نہیں',
      );
    }

    try {
      final updates = <String, dynamic>{
        'stage': toStage.dbValue,
        'updated_by': actorId,
        ...stageData,
      };

      if (toStage == DealStage.closed) {
        updates['closed_at'] = DateTime.now().toIso8601String();
      }

      final data = await _client
          .from('deals')
          .update(updates)
          .eq('id', dealId)
          .eq('dealer_id', dealerId)
          .select()
          .single();

      final updated = Deal.fromMap(data);

      // Immutable event log
      await _logEvent(
        dealId: dealId,
        dealerId: dealerId,
        kind: 'stage_change',
        fromStage: fromStage.dbValue,
        toStage: toStage.dbValue,
        actorId: actorId,
        meta: stageData,
      );

      // Update property status to match deal stage
      if (data['property_id'] != null) {
        await _syncPropertyStatus(
          propertyId: data['property_id'] as String,
          dealerId: dealerId,
          dealStage: toStage,
        );
      }

      return updated;
    } catch (e) {
      throw mapException(e);
    }
  }

  /// Set token details (conditional or confirmed).
  Future<Deal> setToken({
    required String dealId,
    required String dealerId,
    required TokenType tokenType,
    required int tokenRs,
    required DateTime tokenExpiresAt,
    String? termText,
    String? termAudioUrl,
    required String actorId,
  }) async {
    return advanceStage(
      dealId: dealId,
      dealerId: dealerId,
      fromStage: DealStage.inquiry,
      toStage: DealStage.token,
      actorId: actorId,
      stageData: {
        'token_type': tokenType.dbValue,
        'token_rs': tokenRs,
        'token_date': DateTime.now().toIso8601String().split('T').first,
        'token_expires_at': tokenExpiresAt.toIso8601String(),
        'token_terms_text': termText,
        'token_terms_audio_url': termAudioUrl,
      },
    );
  }

  /// Set bayana details.
  Future<Deal> setBayana({
    required String dealId,
    required String dealerId,
    required int bayanaRs,
    DateTime? bayanaDueAt,
    required String actorId,
  }) async {
    return advanceStage(
      dealId: dealId,
      dealerId: dealerId,
      fromStage: DealStage.token,
      toStage: DealStage.bayana,
      actorId: actorId,
      stageData: {
        'bayana_rs': bayanaRs,
        'bayana_date': DateTime.now().toIso8601String().split('T').first,
        'bayana_due_at': bayanaDueAt?.toIso8601String(),
      },
    );
  }

  /// Mark deal lost.
  Future<Deal> markLost({
    required String dealId,
    required String dealerId,
    required DealStage fromStage,
    required LostReason reason,
    String? note,
    required String actorId,
  }) async {
    return advanceStage(
      dealId: dealId,
      dealerId: dealerId,
      fromStage: fromStage,
      toStage: DealStage.lost,
      actorId: actorId,
      stageData: {
        'lost_reason': reason.dbValue,
        'lost_note': note,
      },
    );
  }

  /// Update commission splits. Validates sum = 100%.
  Future<void> updateSplits({
    required String dealId,
    required String dealerId,
    required List<Map<String, dynamic>> splits,
    required String updatedBy,
  }) async {
    // Validate sum
    final total = splits.fold<double>(
      0, (sum, s) => sum + ((s['pct'] as num?)?.toDouble() ?? 0));
    if ((total - 100).abs() > 0.01) {
      throw FinancialIntegrityError(
        'حصے کا مجموعہ 100% ہونا ضروری ہے — ابھی: ${total.toStringAsFixed(1)}%',
      );
    }

    try {
      // Delete existing splits (soft delete)
      await _client.from('deal_splits').update({
        'deleted_at': DateTime.now().toIso8601String(),
        'deleted_by': updatedBy,
      })
      .eq('deal_id', dealId)
      .eq('dealer_id', dealerId)
      .isFilter('deleted_at', null);

      // Insert new splits
      for (final split in splits) {
        await _client.from('deal_splits').insert({
          'deal_id': dealId,
          'dealer_id': dealerId,
          'user_id': split['user_id'],
          'pct': split['pct'],
          'paid_rs': 0,
          'created_by': updatedBy,
        });
      }
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<void> updateDeal({
    required String dealId,
    required String dealerId,
    required Map<String, dynamic> updates,
  }) async {
    try {
      await _client
          .from('deals')
          .update(updates)
          .eq('id', dealId)
          .eq('dealer_id', dealerId);
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<void> softDeleteDeal({
    required String dealId,
    required String dealerId,
    required String deletedBy,
  }) async {
    try {
      await _client.from('deals').update({
        'deleted_at': DateTime.now().toIso8601String(),
        'deleted_by': deletedBy,
      })
      .eq('id', dealId)
      .eq('dealer_id', dealerId);
    } catch (e) {
      throw mapException(e);
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<void> _logEvent({
    required String dealId,
    required String dealerId,
    required String kind,
    String? fromStage,
    String? toStage,
    String? actorId,
    Map<String, dynamic> meta = const {},
  }) async {
    try {
      await _client.from('deal_events').insert({
        'deal_id': dealId,
        'dealer_id': dealerId,
        'kind': kind,
        'from_stage': fromStage,
        'to_stage': toStage,
        'actor_id': actorId,
        'meta': meta,
      });
    } catch (_) {
      // Event logging is non-fatal
    }
  }

  Future<void> _syncPropertyStatus({
    required String propertyId,
    required String dealerId,
    required DealStage dealStage,
  }) async {
    final propStatus = switch (dealStage) {
      DealStage.token    => 'token_given',
      DealStage.bayana   => 'bayana_done',
      DealStage.registry => 'bayana_done',
      DealStage.closed   => 'sold',
      DealStage.lost     => 'available',
      _                  => null,
    };
    if (propStatus == null) return;

    try {
      await _client.from('properties').update({'status': propStatus})
          .eq('id', propertyId)
          .eq('dealer_id', dealerId);
    } catch (_) {}
  }
}

final dealsRepositoryProvider = Provider<DealsRepository>((ref) {
  return DealsRepository(ref.watch(supabaseClientProvider));
});
