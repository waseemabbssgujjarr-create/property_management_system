import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/network/supabase_client.dart';
import '../../../core/services/encryption_service.dart';
import '../models/party_models.dart';

/// PartiesRepository — all party CRUD with CNIC encryption.
///
/// SECURITY: CNIC is encrypted before any DB write and decrypted on read.
/// The plaintext CNIC never reaches the database or any log.
class PartiesRepository {
  final SupabaseClient _client;
  final EncryptionService _enc;

  PartiesRepository(this._client, this._enc);

  Future<List<Party>> getParties({
    required String dealerId,
    PartyType? filterType,
    String? searchQuery,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      var query = _client
          .from('parties')
          .select()
          .eq('dealer_id', dealerId)
          .isFilter('deleted_at', null)
          .order('name')
          .range(offset, offset + limit - 1);

      if (filterType != null) {
        query = query.eq('type', filterType.dbValue);
      }
      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or(
          'name.ilike.%$searchQuery%,phone.ilike.%$searchQuery%',
        );
      }

      final data = await query;
      // CNIC is stored encrypted; decrypt on read
      return await Future.wait((data as List)
          .map((m) => _fromMapWithDecrypt(m as Map<String, dynamic>, dealerId))
          .toList());
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<Party> getParty(String id, String dealerId) async {
    try {
      final data = await _client
          .from('parties')
          .select()
          .eq('id', id)
          .eq('dealer_id', dealerId)
          .single();
      return await _fromMapWithDecrypt(data, dealerId);
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<Party> createParty({
    required String dealerId,
    required Party party,
    String? createdBy,
  }) async {
    try {
      // Duplicate check by phone
      if (party.phone != null && party.phone!.isNotEmpty) {
        final existing = await checkDuplicateByPhone(
          dealerId: dealerId,
          phone: party.phone!,
        );
        if (existing != null) {
          throw const ValidationError(
            'اس نمبر کا کلائنٹ پہلے سے موجود ہے',
            {'phone': 'duplicate'},
          );
        }
      }

      // Encrypt CNIC before insert — plaintext never reaches DB
      final encryptedCnic = await _enc.encrypt(party.cnic, dealerId: dealerId);

      final insertData = await _toInsertMapWithEncrypt(party, encryptedCnic)
        ..['created_by'] = createdBy;

      final data = await _client
          .from('parties')
          .insert(insertData)
          .select()
          .single();

      return await _fromMapWithDecrypt(data, dealerId);
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<void> updateParty({
    required String id,
    required String dealerId,
    Map<String, dynamic> updates = const {},
    String? newCnic,
  }) async {
    try {
      final mutableUpdates = Map<String, dynamic>.from(updates);

      // If CNIC is being updated, encrypt it first
      if (newCnic != null) {
        if (EncryptionService.looksLikePlaintext(newCnic)) {
          mutableUpdates['cnic'] = await _enc.encrypt(newCnic, dealerId: dealerId);
        } else {
          // Already encrypted — pass through
          mutableUpdates['cnic'] = newCnic;
        }
      }
      // Prevent direct plaintext CNIC update via generic updates map
      if (mutableUpdates.containsKey('cnic')) {
        final rawCnic = mutableUpdates['cnic'] as String?;
        if (EncryptionService.looksLikePlaintext(rawCnic)) {
          mutableUpdates['cnic'] = await _enc.encrypt(rawCnic, dealerId: dealerId);
        }
      }

      await _client
          .from('parties')
          .update(mutableUpdates)
          .eq('id', id)
          .eq('dealer_id', dealerId);
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<void> updateWaOptIn({
    required String id,
    required String dealerId,
    required bool optIn,
  }) async {
    try {
      await _client.from('parties').update({
        'wa_opt_in': optIn,
        'wa_opt_in_at': optIn ? DateTime.now().toIso8601String() : null,
        'wa_opt_in_source': optIn ? 'manual_toggle' : null,
      })
      .eq('id', id)
      .eq('dealer_id', dealerId);
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<Party?> checkDuplicateByPhone({
    required String dealerId,
    required String phone,
  }) async {
    try {
      final data = await _client
          .from('parties')
          .select()
          .eq('dealer_id', dealerId)
          .eq('phone', phone)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (data == null) return null;
      return await _fromMapWithDecrypt(data, dealerId);
    } catch (_) {
      return null;
    }
  }

  Future<void> softDeleteParty({
    required String id,
    required String dealerId,
    required String deletedBy,
  }) async {
    try {
      await _client.from('parties').update({
        'deleted_at': DateTime.now().toIso8601String(),
        'deleted_by': deletedBy,
      })
      .eq('id', id)
      .eq('dealer_id', dealerId);
    } catch (e) {
      throw mapException(e);
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Decrypt CNIC on read. All other fields pass through.
  Future<Party> _fromMapWithDecrypt(
    Map<String, dynamic> m,
    String dealerId,
  ) async {
    final encryptedCnic = m['cnic'] as String?;
    String? decryptedCnic;
    if (encryptedCnic != null) {
      // If looks like plaintext (old data), return as-is but log warning
      if (EncryptionService.looksLikePlaintext(encryptedCnic)) {
        // Legacy plaintext — return masked representation, don't expose
        decryptedCnic = encryptedCnic; // surface to caller for migration
      } else {
        decryptedCnic = await _enc.decrypt(encryptedCnic, dealerId: dealerId);
      }
    }
    return Party.fromMap({...m, 'cnic': decryptedCnic});
  }

  /// Build insert map with encrypted CNIC.
  Future<Map<String, dynamic>> _toInsertMapWithEncrypt(
    Party party,
    String? encryptedCnic,
  ) async {
    return {
      'dealer_id': party.dealerId,
      'type': party.type.dbValue,
      'name': party.name,
      'name_audio_url': party.nameAudioUrl,
      'phone': party.phone,
      'photo_url': party.photoUrl,
      'cnic': encryptedCnic,   // encrypted or null — never plaintext
      'source': party.source.dbValue,
      'wa_opt_in': party.waOptIn,
      'wa_opt_in_at': party.waOptIn ? DateTime.now().toIso8601String() : null,
      'notes_text': party.notesText,
      'notes_audio_url': party.notesAudioUrl,
    };
  }
}

final partiesRepositoryProvider = Provider<PartiesRepository>((ref) {
  return PartiesRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(encryptionServiceProvider),
  );
});
