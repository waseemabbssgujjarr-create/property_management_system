import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/network/supabase_client.dart';
import '../models/followup_models.dart';

class FollowupsRepository {
  final SupabaseClient _client;
  FollowupsRepository(this._client);

  Future<List<Followup>> getFollowups({
    required String dealerId,
    bool todayOnly = false,
    bool pendingOnly = true,
    int limit = 50,
  }) async {
    try {
      var query = _client
          .from('followups')
          .select('*, parties(name, phone, photo_url)')
          .eq('dealer_id', dealerId)
          .isFilter('deleted_at', null);

      if (pendingOnly) {
        query = query.eq('status', 'pending');
      }
      if (todayOnly) {
        final now = DateTime.now();
        final todayStart = DateTime(now.year, now.month, now.day);
        final tomorrowStart = todayStart.add(const Duration(days: 1));
        query = query
            .gte('due_at', todayStart.toIso8601String())
            .lt('due_at', tomorrowStart.toIso8601String());
      }

      final data = await query.order('due_at').limit(limit);
      return (data as List)
          .map((m) => Followup.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<Followup> createFollowup({
    required String dealerId,
    String? dealId,
    String? partyId,
    required FollowupKind kind,
    required DateTime dueAt,
    String? noteText,
    String? noteAudioUrl,
    String? assignedTo,
    required String createdBy,
  }) async {
    try {
      final data = await _client.from('followups').insert({
        'dealer_id': dealerId,
        'deal_id': dealId,
        'party_id': partyId,
        'assigned_to': assignedTo,
        'kind': kind.dbValue,
        'due_at': dueAt.toIso8601String(),
        'note_text': noteText,
        'note_audio_url': noteAudioUrl,
        'status': 'pending',
        'created_by': createdBy,
      }).select('*, parties(name, phone, photo_url)').single();
      return Followup.fromMap(data);
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<void> markDone(String id, String dealerId) async {
    try {
      await _client.from('followups').update({
        'status': 'done',
        'done_at': DateTime.now().toIso8601String(),
      })
      .eq('id', id)
      .eq('dealer_id', dealerId);
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<void> snooze(String id, String dealerId, DateTime until) async {
    try {
      await _client.from('followups').update({
        'status': 'snoozed',
        'snoozed_until': until.toIso8601String(),
      })
      .eq('id', id)
      .eq('dealer_id', dealerId);
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<void> cancel(String id, String dealerId) async {
    try {
      await _client.from('followups').update({'status': 'cancelled'})
          .eq('id', id)
          .eq('dealer_id', dealerId);
    } catch (e) {
      throw mapException(e);
    }
  }
}

final followupsRepositoryProvider = Provider<FollowupsRepository>((ref) {
  return FollowupsRepository(ref.watch(supabaseClientProvider));
});
