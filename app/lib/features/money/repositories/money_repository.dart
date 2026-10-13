import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/network/supabase_client.dart';
import '../../../core/platform/file_support.dart';
import '../models/payment_models.dart';

/// Money repository — append-only payments, receipt generation.
///
/// Financial integrity rules enforced here AND at DB level:
/// - amount_rs >= 0
/// - idempotency_key unique (prevents duplicate submissions)
/// - receipt_no sequential, concurrency-safe (DB function)
/// - no UPDATE or DELETE on payments — corrections use reversal rows
class MoneyRepository {
  final SupabaseClient _client;
  MoneyRepository(this._client);

  // ── Record payment (the 20-second flow core) ─────────────────────────────

  Future<Payment> recordPayment({
    required String dealerId,
    required PaymentKind kind,
    required int amountRs,
    required String direction,
    required String method,
    String? dealId,
    String? noteText,
    String? noteAudioUrl,
    String? receiptPhotoUrl,
    String? paidToUserId,
    String? category,
    bool generateReceipt = false,
    required String createdBy,
  }) async {
    if (amountRs < 0) {
      throw const FinancialIntegrityError('رقم صفر سے کم نہیں ہو سکتی');
    }

    try {
      final idempotencyKey = const Uuid().v4();
      String? receiptNo;

      // Generate receipt number for money-in payments
      if (generateReceipt || kind == PaymentKind.tokenIn ||
          kind == PaymentKind.bayanaIn || kind == PaymentKind.commissionIn) {
        receiptNo = await _nextReceiptNo(dealerId);
      }

      final data = await _client.from('payments').insert({
        'dealer_id': dealerId,
        'deal_id': dealId,
        'kind': kind.dbValue,
        'amount_rs': amountRs,
        'direction': direction,
        'method': method,
        'receipt_no': receiptNo,
        'receipt_photo_url': receiptPhotoUrl,
        'paid_to_user_id': paidToUserId,
        'category': category,
        'note_text': noteText,
        'note_audio_url': noteAudioUrl,
        'occurred_at': DateTime.now().toIso8601String(),
        'idempotency_key': idempotencyKey,
        'created_by': createdBy,
      }).select().single();

      return Payment.fromMap(data);
    } catch (e) {
      throw mapException(e);
    }
  }

  /// Record a reversal (not an update — append-only).
  Future<Payment> reversePayment({
    required String originalPaymentId,
    required String dealerId,
    required String reason,
    required String createdBy,
  }) async {
    try {
      // Fetch original
      final orig = await _client
          .from('payments')
          .select()
          .eq('id', originalPaymentId)
          .eq('dealer_id', dealerId)
          .single();

      final original = Payment.fromMap(orig);

      // Insert reversal row — the reversal_of_id links it to the original.
      // The original payment is NOT mutated (append-only invariant).
      // `reversed_by_id` on the original is intentionally left null because
      // the payments table has no UPDATE RLS policy. Callers determine
      // if a payment is reversed by querying for its reversal_of_id counterpart.
      final reversalData = await _client.from('payments').insert({
        'dealer_id': dealerId,
        'deal_id': original.dealId,
        'kind': 'reversal',
        'amount_rs': original.amountRs,
        'direction': original.direction == 'in' ? 'out' : 'in',
        'method': original.method,
        'reversal_of_id': originalPaymentId,
        'note_text': reason,
        'occurred_at': DateTime.now().toIso8601String(),
        'idempotency_key': const Uuid().v4(),
        'created_by': createdBy,
      }).select().single();

      // NOTE: We do NOT update the original payment's reversed_by_id column.
      // The payments table is append-only (no UPDATE RLS policy).
      // To check if payment X is reversed: query WHERE reversal_of_id = X.

      return Payment.fromMap(reversalData);
    } catch (e) {
      throw mapException(e);
    }
  }

  // ── Queries ───────────────────────────────────────────────────────────────

  Future<List<Payment>> getPayments({
    required String dealerId,
    String? dealId,
    PaymentKind? kind,
    DateTime? from,
    DateTime? to,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      var query = _client
          .from('payments')
          .select()
          .eq('dealer_id', dealerId);

      if (dealId != null) query = query.eq('deal_id', dealId);
      if (kind != null) query = query.eq('kind', kind.dbValue);
      if (from != null) query = query.gte('occurred_at', from.toIso8601String());
      if (to != null) query = query.lte('occurred_at', to.toIso8601String());

      final data = await query
          .order('occurred_at', ascending: false)
          .range(offset, offset + limit - 1);
      return (data as List)
          .map((m) => Payment.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw mapException(e);
    }
  }

  Future<Payment> getPayment(String id, String dealerId) async {
    try {
      final data = await _client
          .from('payments')
          .select()
          .eq('id', id)
          .eq('dealer_id', dealerId)
          .single();
      return Payment.fromMap(data);
    } catch (e) {
      throw mapException(e);
    }
  }

  /// Monthly totals summary.
  Future<Map<String, int>> getMonthlyTotals({
    required String dealerId,
    required DateTime monthStart,
    required DateTime monthEnd,
  }) async {
    try {
      final data = await _client
          .from('payments')
          .select('amount_rs, direction, kind')
          .eq('dealer_id', dealerId)
          .gte('occurred_at', monthStart.toIso8601String())
          .lt('occurred_at', monthEnd.toIso8601String());

      int totalIn = 0, totalOut = 0, totalComm = 0, totalExpense = 0;

      for (final row in data as List) {
        final amount = row['amount_rs'] as int? ?? 0;
        final dir = row['direction'] as String;
        final k = row['kind'] as String;

        if (dir == 'in') totalIn += amount;
        if (dir == 'out') totalOut += amount;
        if (k == 'commission_in') totalComm += amount;
        if (k == 'expense') totalExpense += amount;
      }

      return {
        'total_in': totalIn,
        'total_out': totalOut,
        'commission_received': totalComm,
        'expenses': totalExpense,
        'net': totalIn - totalOut,
      };
    } catch (e) {
      throw mapException(e);
    }
  }

  // ── Receipt upload ────────────────────────────────────────────────────────

  Future<String> uploadReceiptPhoto({
    required String dealerId,
    required String paymentId,
    required String localPath,
  }) async {
    if (kIsWeb) throw UnsupportedError('File upload not supported on web');
    try {
      final file = File(localPath);
      final ext = localPath.split('.').last;
      final storagePath = '$dealerId/receipts/$paymentId.$ext';

      await _client.storage
          .from('documents')
          .upload(storagePath, file);

      return _client.storage.from('documents').getPublicUrl(storagePath);
    } catch (e) {
      throw mapException(e);
    }
  }

  // ── Staff commission summary (used by StaffScreen) ───────────────────────

  Future<List<Map<String, dynamic>>> getStaffCommissionSummary({
    required String dealerId,
    required DateTime monthStart,
    required DateTime monthEnd,
  }) async {
    try {
      final data = await _client.rpc('get_staff_commission_summary', params: {
        'p_dealer_id':  dealerId,
        'p_month_start': monthStart.toIso8601String(),
        'p_month_end':   monthEnd.toIso8601String(),
      });
      return (data as List).cast<Map<String, dynamic>>();
    } catch (e) {
      throw mapException(e);
    }
  }

  // ── Private ───────────────────────────────────────────────────────────────

  Future<String> _nextReceiptNo(String dealerId) async {
    final year = DateTime.now().year;
    final result = await _client.rpc('next_receipt_no', params: {
      'p_dealer_id': dealerId,
      'p_year': year,
    });
    return result as String;
  }
}

final moneyRepositoryProvider = Provider<MoneyRepository>((ref) {
  return MoneyRepository(ref.watch(supabaseClientProvider));
});
