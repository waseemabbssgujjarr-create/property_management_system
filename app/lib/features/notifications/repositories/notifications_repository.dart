import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/network/supabase_client.dart';

class NotificationsRepository {
  final SupabaseClient _client;
  NotificationsRepository(this._client);

  Future<List<Map<String, dynamic>>> getNotifications({
    required String dealerId,
    int limit = 30,
  }) async {
    try {
      final data = await _client
          .from('notifications')
          .select()
          .eq('dealer_id', dealerId)
          .order('created_at', ascending: false)
          .limit(limit);
      return (data as List).cast<Map<String, dynamic>>();
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<void> markAllRead(String dealerId) async {
    try {
      await _client
          .from('notifications')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('dealer_id', dealerId)
          .isFilter('read_at', null);
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<void> markRead(String id, String dealerId) async {
    try {
      await _client
          .from('notifications')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('id', id)
          .eq('dealer_id', dealerId);
    } catch (e) {
      throw mapException(e);
    }
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  return NotificationsRepository(ref.watch(supabaseClientProvider));
});
