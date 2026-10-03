import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/network/supabase_client.dart';
import '../models/wa_connection_models.dart';

/// WaConnectionRepository — manage WhatsApp connections via our own WA API.
///
/// Security contract:
/// - This repository NEVER receives or returns API keys or webhook secrets
/// - Credential storage is delegated to the `wa-connect` Edge Function
///   which calls `store_wa_credentials()` DB function (service_role only)
/// - The Flutter client only ever sees safe metadata (status, phone, display name)
/// - Connection ID is masked when shown in UI
class WaConnectionRepository {
  final SupabaseClient _client;
  WaConnectionRepository(this._client);

  // ── Read ──────────────────────────────────────────────────────────────────

  Future<WaConnection?> getConnection(String dealerId) async {
    try {
      final data = await _client
          .from('whatsapp_connections')
          .select(
            'id, dealer_id, office_id, connection_id, api_base_url, '
            'phone_number, display_name, status, error_message, '
            'last_health_check_at, last_webhook_at, last_message_sent_at, '
            'created_at, updated_at',
            // NOTE: api_key_encrypted and webhook_secret_encrypted are
            // intentionally NOT selected here — they must never reach the client
          )
          .eq('dealer_id', dealerId)
          .eq('status', 'active')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (data == null) return null;
      return WaConnection.fromMap(data as Map<String, dynamic>);
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<List<WaConnection>> getAllConnections(String dealerId) async {
    try {
      final data = await _client
          .from('whatsapp_connections')
          .select(
            'id, dealer_id, office_id, connection_id, api_base_url, '
            'phone_number, display_name, status, error_message, '
            'last_health_check_at, last_webhook_at, last_message_sent_at, '
            'created_at, updated_at',
          )
          .eq('dealer_id', dealerId)
          .order('created_at', ascending: false);

      return (data as List)
          .map((m) => WaConnection.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw mapException(e);
    }
  }

  // ── Connect (delegates to Edge Function for secure credential storage) ────

  /// Connect a WhatsApp account.
  ///
  /// The Edge Function (`wa-connect`) receives the credentials,
  /// validates them against our WA API, then stores them encrypted
  /// using `store_wa_credentials()`.
  ///
  /// After this call, the API key and webhook secret are GONE from Dart state.
  Future<WaConnection> connect({
    required String dealerId,
    required WaConnectionInput input,
    required String connectedBy,
  }) async {
    try {
      final result = await _client.functions.invoke(
        'wa-connect',
        body: {
          'dealer_id':      dealerId,
          'connection_id':  input.connectionId,
          'api_key':        input.apiKey,          // sent once, never stored in Dart after
          'webhook_secret': input.webhookSecret,   // sent once, never stored in Dart after
          'api_base_url':   input.apiBaseUrl,
          'phone_number':   input.phoneNumber,
          'display_name':   input.displayName,
          'connected_by':   connectedBy,
        },
      );

      if (result.status != 200) {
        final data = result.data as Map<String, dynamic>?;
        throw ServerError(
          data?['error'] as String? ?? 'Connection failed',
          result.status,
        );
      }

      final data = result.data as Map<String, dynamic>;
      return WaConnection.fromMap(data['connection'] as Map<String, dynamic>);
    } catch (e) {
      if (e is AppError) rethrow;
      throw mapException(e);
    }
  }

  // ── Health check ──────────────────────────────────────────────────────────

  Future<WaHealthCheckResult> testConnection({
    required String dealerId,
    required String connectionId,
  }) async {
    try {
      final result = await _client.functions.invoke(
        'wa-health-check',
        body: {
          'dealer_id':     dealerId,
          'connection_id': connectionId,
        },
      );

      final data = result.data as Map<String, dynamic>?;
      final isHealthy = result.status == 200 && (data?['healthy'] as bool? ?? false);

      return WaHealthCheckResult(
        isHealthy: isHealthy,
        phoneNumber: data?['phone_number'] as String?,
        displayName: data?['display_name'] as String?,
        errorMessage: isHealthy ? null : (data?['error'] as String?),
        checkedAt: DateTime.now(),
      );
    } catch (e) {
      return WaHealthCheckResult(
        isHealthy: false,
        errorMessage: e.toString(),
        checkedAt: DateTime.now(),
      );
    }
  }

  // ── Disconnect ────────────────────────────────────────────────────────────

  /// Disconnect a WhatsApp connection.
  /// Historical messages and conversations are preserved.
  Future<void> disconnect({
    required String dealerId,
    required String connectionId,
    required String disconnectedBy,
  }) async {
    try {
      await _client
          .from('whatsapp_connections')
          .update({
            'status':           'disconnected',
            'disconnected_at':  DateTime.now().toIso8601String(),
            'updated_by':       disconnectedBy,
            'error_message':    null,
          })
          .eq('dealer_id', dealerId)
          .eq('connection_id', connectionId);
    } catch (e) {
      throw mapException(e);
    }
  }

  // ── Outbound message queuing ──────────────────────────────────────────────

  Future<void> queueOutboundMessage({
    required String dealerId,
    required String connectionId,
    required String toPhone,
    required String messageBody,
    required String idempotencyKey,
    String? partyId,
    String? dealId,
  }) async {
    try {
      await _client.from('wa_outbound_queue').insert({
        'dealer_id':        dealerId,
        'connection_id':    connectionId,
        'party_id':         partyId,
        'deal_id':          dealId,
        'to_phone':         toPhone,
        'message_type':     'text',
        'message_body':     messageBody,
        'idempotency_key':  idempotencyKey,
        'status':           'queued',
      });
    } catch (e) {
      throw mapException(e);
    }
  }
}

final waConnectionRepositoryProvider = Provider<WaConnectionRepository>((ref) {
  return WaConnectionRepository(ref.watch(supabaseClientProvider));
});

final waConnectionProvider = FutureProvider.family<WaConnection?, String>(
  (ref, dealerId) async {
    if (dealerId.isEmpty) return null;
    return ref.read(waConnectionRepositoryProvider).getConnection(dealerId);
  },
);
