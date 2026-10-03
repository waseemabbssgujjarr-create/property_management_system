import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/network/supabase_client.dart';
import '../models/auth_models.dart';

/// Auth repository — encapsulates all Supabase Auth calls.
/// Never expose raw Supabase types to the feature layer.
class AuthRepository {
  final SupabaseClient _client;

  AuthRepository(this._client);

  // ── OTP ──────────────────────────────────────────────────────────────────

  /// Send OTP via WhatsApp (primary) with SMS fallback.
  /// Rate-limited on server side: max 3 attempts per 15 minutes.
  Future<void> sendOtp(String phone) async {
    try {
      // Normalize Pakistani phone number to E.164
      final normalized = _normalizePhone(phone);
      await _client.auth.signInWithOtp(
        phone: normalized,
        channel: OtpChannel.sms, // Supabase Auth OTP; WhatsApp delivery via Edge Function
      );
    } catch (e) {
      throw mapException(e);
    }
  }

  /// Verify OTP entered by user.
  Future<AuthResponse> verifyOtp({
    required String phone,
    required String token,
  }) async {
    try {
      final normalized = _normalizePhone(phone);
      final response = await _client.auth.verifyOTP(
        phone: normalized,
        token: token,
        type: OtpType.sms,
      );
      return response;
    } catch (e) {
      throw mapException(e);
    }
  }

  /// Request voice OTP (calls the voice-otp-call Edge Function).
  /// Returns true if call was initiated, false if no provider is configured.
  /// Throws OtpError only on hard delivery failures (not on missing config).
  Future<bool> requestVoiceOtp(String phone) async {
    try {
      final normalized = _normalizePhone(phone);
      // We need the current session's OTP token to pass to the voice call.
      // Supabase Auth doesn't expose the raw OTP, so we trigger via Edge Function
      // which handles OTP retrieval internally.
      final result = await _client.functions.invoke(
        'voice-otp-call',
        body: {'phone': normalized},
      );

      final data = result.data as Map<String, dynamic>?;

      // Edge Function returned an error code
      if (result.status != 200) {
        final errorCode = data?['error_code'] as String?;
        if (errorCode == 'provider_not_configured') {
          // Not a fatal error — just no voice provider configured yet
          return false;
        }
        throw OtpError(
          OtpErrorKind.sendFailed,
          data?['error'] as String? ?? 'Voice call failed',
        );
      }

      return true;
    } on FunctionException catch (e) {
      // Edge Function not deployed yet
      return false;
    } catch (e) {
      if (e is OtpError) rethrow;
      throw mapException(e);
    }
  }

  // ── Session ───────────────────────────────────────────────────────────────

  /// Load the full session for the currently authenticated user.
  /// Queries `users` and `dealers` tables.
  Future<AppSession?> loadSession() async {
    try {
      final authUser = _client.auth.currentUser;
      if (authUser == null) return null;

      // Get user record
      final userResponse = await _client
          .from('users')
          .select('*, dealers(*)')
          .eq('phone', authUser.phone ?? '')
          .eq('active', true)
          .single();

      final dealer = userResponse['dealers'] as Map<String, dynamic>;
      return AppSession.fromMaps(user: userResponse, dealer: dealer);
    } catch (e) {
      throw mapException(e);
    }
  }

  /// Check if user has completed onboarding (dealer record exists).
  Future<bool> hasCompletedOnboarding(String phone) async {
    try {
      final normalized = _normalizePhone(phone);
      final result = await _client
          .from('users')
          .select('id')
          .eq('phone', normalized)
          .maybeSingle();
      return result != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Normalize to Pakistani E.164 format.
  /// Handles: 03xx, +923xx, 923xx
  String _normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.startsWith('92')) return '+$digits';
    if (digits.startsWith('0')) return '+92${digits.substring(1)}';
    if (digits.length == 10) return '+92$digits';
    return '+$digits';
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});
