import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_error.dart';
import '../repositories/auth_repository.dart';

/// OTP state machine
enum OtpStep { enterPhone, enterCode, verifying, success, error }

class OtpState {
  final OtpStep step;
  final String phone;
  final String? error;
  final bool isSending;
  final bool isVerifying;
  final int resendCooldownSeconds;

  const OtpState({
    this.step = OtpStep.enterPhone,
    this.phone = '',
    this.error,
    this.isSending = false,
    this.isVerifying = false,
    this.resendCooldownSeconds = 0,
  });

  OtpState copyWith({
    OtpStep? step,
    String? phone,
    String? error,
    bool? isSending,
    bool? isVerifying,
    int? resendCooldownSeconds,
    bool clearError = false,
  }) {
    return OtpState(
      step: step ?? this.step,
      phone: phone ?? this.phone,
      error: clearError ? null : (error ?? this.error),
      isSending: isSending ?? this.isSending,
      isVerifying: isVerifying ?? this.isVerifying,
      resendCooldownSeconds: resendCooldownSeconds ?? this.resendCooldownSeconds,
    );
  }
}

class OtpNotifier extends Notifier<OtpState> {
  @override
  OtpState build() => const OtpState();

  Future<bool> sendOtp(String phone) async {
    state = state.copyWith(
      step: OtpStep.enterPhone,
      isSending: true,
      phone: phone,
      clearError: true,
    );

    try {
      await ref.read(authRepositoryProvider).sendOtp(phone);
      state = state.copyWith(
        step: OtpStep.enterCode,
        isSending: false,
        resendCooldownSeconds: 60,
      );
      _startCooldown();
      return true;
    } catch (e) {
      final err = e is AppError ? e : mapException(e);
      state = state.copyWith(
        step: OtpStep.enterPhone,
        isSending: false,
        error: err.message,
      );
      return false;
    }
  }

  Future<bool> verifyOtp(String code) async {
    if (state.phone.isEmpty) return false;

    state = state.copyWith(
      step: OtpStep.verifying,
      isVerifying: true,
      clearError: true,
    );

    try {
      await ref.read(authRepositoryProvider).verifyOtp(
        phone: state.phone,
        token: code,
      );
      state = state.copyWith(
        step: OtpStep.success,
        isVerifying: false,
      );
      return true;
    } on OtpError catch (e) {
      state = state.copyWith(
        step: OtpStep.enterCode,
        isVerifying: false,
        error: e.message,
      );
      return false;
    } catch (e) {
      final err = mapException(e);
      state = state.copyWith(
        step: OtpStep.enterCode,
        isVerifying: false,
        error: err.message,
      );
      return false;
    }
  }

  Future<void> requestVoiceOtp() async {
    if (state.phone.isEmpty) return;
    try {
      final ok = await ref.read(authRepositoryProvider).requestVoiceOtp(state.phone);
      if (!ok) {
        // Provider not configured — inform user to use SMS/WhatsApp OTP instead
        state = state.copyWith(
          error: 'آواز سے کوڈ ابھی دستیاب نہیں — WhatsApp یا SMS کوڈ استعمال کریں',
        );
      }
    } catch (e) {
      if (e is OtpError) {
        state = state.copyWith(error: e.message);
      }
    }
  }

  Future<bool> resendOtp() async {
    if (state.resendCooldownSeconds > 0) return false;
    return sendOtp(state.phone);
  }

  void setPhone(String phone) {
    state = state.copyWith(phone: phone, clearError: true);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  void _startCooldown() async {
    for (int i = 60; i >= 0; i--) {
      await Future.delayed(const Duration(seconds: 1));
      if (!state.isSending) {
        state = state.copyWith(resendCooldownSeconds: i);
      }
    }
  }
}

final otpProvider = NotifierProvider<OtpNotifier, OtpState>(OtpNotifier.new);
