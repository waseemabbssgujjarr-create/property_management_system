import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/network/supabase_client.dart';
import '../models/tenancy_models.dart';

/// Tenancy repository — dealer, office, user/staff management.
class TenancyRepository {
  final SupabaseClient _client;
  TenancyRepository(this._client);

  // ── Dealer ────────────────────────────────────────────────────────────────

  Future<DealerProfile> getDealerProfile(String dealerId) async {
    try {
      final data = await _client
          .from('dealers')
          .select()
          .eq('id', dealerId)
          .single();
      return DealerProfile.fromMap(data);
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<void> updateDealerProfile({
    required String dealerId,
    String? name,
    String? city,
    List<String>? areas,
    String? uiMode,
    bool? voiceEnabled,
    String? language,
    String? logoUrl,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (city != null) updates['city'] = city;
      if (areas != null) updates['areas'] = areas;
      if (uiMode != null) updates['ui_mode'] = uiMode;
      if (voiceEnabled != null) updates['voice_enabled'] = voiceEnabled;
      if (language != null) updates['language'] = language;
      if (logoUrl != null) updates['logo_url'] = logoUrl;

      await _client
          .from('dealers')
          .update(updates)
          .eq('id', dealerId);
    } catch (e) {
      throw mapException(e);
    }
  }

  // ── Staff ─────────────────────────────────────────────────────────────────

  Future<List<StaffMember>> getStaffList(String dealerId) async {
    try {
      final data = await _client
          .from('users')
          .select()
          .eq('dealer_id', dealerId)
          .eq('active', true)
          .order('role')
          .order('name');
      return (data as List)
          .map((m) => StaffMember.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw mapException(e);
    }
  }

  /// Invite staff member.
  /// Creates user record + sends WhatsApp/SMS invite link.
  Future<StaffMember> inviteStaff({
    required String dealerId,
    required String name,
    required String phone,
    required String role,
    String? officeId,
    double? defaultCommissionPct,
  }) async {
    try {
      // Normalize phone
      final normalized = _normalizePhone(phone);

      // Check for duplicate
      final existing = await _client
          .from('users')
          .select('id')
          .eq('dealer_id', dealerId)
          .eq('phone', normalized)
          .maybeSingle();

      if (existing != null) {
        throw const ValidationError(
          'یہ نمبر پہلے سے موجود ہے',
          {'phone': 'یہ نمبر پہلے سے موجود ہے'},
        );
      }

      final data = await _client.from('users').insert({
        'dealer_id': dealerId,
        'phone': normalized,
        'name': name,
        'role': role,
        'office_id': officeId,
        'default_commission_pct': defaultCommissionPct,
        'active': true,
      }).select().single();

      // Staff invite notification: attempts via Edge Function if available.
      // The Edge Function is not required for Phase 1 — user can log in with OTP.
      // Non-blocking: failure does not prevent the user record from being created.
      _client.functions.invoke('send-staff-invite', body: {
        'user_id': data['id'],
        'dealer_id': dealerId,
        'phone': normalized,
        'name': name,
      }).then((_) {}).catchError((e) {
        // Edge Function not deployed yet — log warning, don't throw
        debugPrint('send-staff-invite: not deployed or failed (non-fatal): $e');
      });

      return StaffMember.fromMap(data);
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<void> updateStaffRole({
    required String userId,
    required String dealerId,
    required String role,
  }) async {
    try {
      await _client
          .from('users')
          .update({'role': role})
          .eq('id', userId)
          .eq('dealer_id', dealerId);
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<void> deactivateStaff({
    required String userId,
    required String dealerId,
  }) async {
    try {
      await _client
          .from('users')
          .update({'active': false, 'deleted_at': DateTime.now().toIso8601String()})
          .eq('id', userId)
          .eq('dealer_id', dealerId);
    } catch (e) {
      throw mapException(e);
    }
  }

  String _normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.startsWith('92')) return '+$digits';
    if (digits.startsWith('0')) return '+92${digits.substring(1)}';
    if (digits.length == 10) return '+92$digits';
    return '+$digits';
  }
}

final tenancyRepositoryProvider = Provider<TenancyRepository>((ref) {
  return TenancyRepository(ref.watch(supabaseClientProvider));
});
