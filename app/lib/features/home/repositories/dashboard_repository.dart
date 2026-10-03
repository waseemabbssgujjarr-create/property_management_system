import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/network/supabase_client.dart';
import '../models/dashboard_models.dart';

/// Dashboard data repository.
/// Fetches the owner's "Aaj ka Hisaab" — today's account summary.
class DashboardRepository {
  final SupabaseClient _client;
  DashboardRepository(this._client);

  Future<DashboardSummary> getDashboardSummary(String dealerId) async {
    try {
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      final todayStart = DateTime(now.year, now.month, now.day);
      final threeDaysLater = now.add(const Duration(days: 3));

      // Run all queries in parallel
      final results = await Future.wait([
        // Expected commission this month (open deals)
        _client.rpc('get_expected_commission_month', params: {
          'p_dealer_id': dealerId,
          'p_month_start': monthStart.toIso8601String(),
        }),

        // Commission received this month
        _client
            .from('payments')
            .select('amount_rs')
            .eq('dealer_id', dealerId)
            .eq('kind', 'commission_in')
            .gte('occurred_at', monthStart.toIso8601String()),

        // Money in today
        _client
            .from('payments')
            .select('amount_rs, direction')
            .eq('dealer_id', dealerId)
            .gte('occurred_at', todayStart.toIso8601String()),

        // Tokens expiring in <= 3 days
        _client
            .from('deals')
            .select('id, deal_price_rs, expected_comm_rs, token_expires_at, buyer_party_id, property_id')
            .eq('dealer_id', dealerId)
            .eq('stage', 'token')
            .lte('token_expires_at', threeDaysLater.toIso8601String())
            .gte('token_expires_at', now.toIso8601String())
            .isFilter('deleted_at', null),

        // Follow-ups due today
        _client
            .from('followups')
            .select('id, party_id, kind, due_at, note_text')
            .eq('dealer_id', dealerId)
            .eq('status', 'pending')
            .gte('due_at', todayStart.toIso8601String())
            .lt('due_at', todayStart.add(const Duration(days: 1)).toIso8601String())
            .order('due_at'),

        // Deals by stage count
        _client
            .from('deals')
            .select('stage')
            .eq('dealer_id', dealerId)
            .isFilter('deleted_at', null)
            .neq('stage', 'closed')
            .neq('stage', 'lost'),
      ]);

      // Parse commission received
      int commissionReceivedRs = 0;
      final commRecords = results[1] as List;
      for (final r in commRecords) {
        commissionReceivedRs += (r['amount_rs'] as int? ?? 0);
      }

      // Parse today's money in/out
      int todayMoneyIn = 0;
      int todayMoneyOut = 0;
      final todayPayments = results[2] as List;
      for (final p in todayPayments) {
        final amount = p['amount_rs'] as int? ?? 0;
        if (p['direction'] == 'in') {
          todayMoneyIn += amount;
        } else {
          todayMoneyOut += amount;
        }
      }

      // Parse expiring tokens
      final expiringTokens = (results[3] as List)
          .map((t) => ExpiringToken.fromMap(t as Map<String, dynamic>))
          .toList();

      // Parse follow-ups
      final followupsDue = (results[4] as List)
          .map((f) => DueTodayFollowup.fromMap(f as Map<String, dynamic>))
          .toList();

      // Parse stage counts
      final stageCounts = <String, int>{};
      final stageRows = results[5] as List;
      for (final r in stageRows) {
        final stage = r['stage'] as String;
        stageCounts[stage] = (stageCounts[stage] ?? 0) + 1;
      }

      // Expected commission (from RPC)
      int expectedCommissionRs = 0;
      try {
        expectedCommissionRs = (results[0] as int?) ?? 0;
      } catch (_) {}

      return DashboardSummary(
        expectedCommissionRs: expectedCommissionRs,
        commissionReceivedRs: commissionReceivedRs,
        todayMoneyIn: todayMoneyIn,
        todayMoneyOut: todayMoneyOut,
        expiringTokens: expiringTokens,
        followupsDueToday: followupsDue,
        stageCounts: stageCounts,
        generatedAt: now,
      );
    } catch (e) {
      throw mapException(e);
    }
  }
}

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(ref.watch(supabaseClientProvider));
});
