import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/services/tts_service.dart';
import '../providers/otp_provider.dart';
import '../providers/session_provider.dart';
import '../repositories/auth_repository.dart';

/// OTP Screen — no-read first.
///
/// Phase 1 (phone entry):
///   Big phone input with Pakistani number hint
///   "کال کریں" voice OTP option
///
/// Phase 2 (code entry):
///   6 large digit boxes (no keyboard confusion)
///   Auto-advance when 6 digits entered
///   Voice OTP option for owners who can't read SMS
///   Resend with 60s cooldown
class OtpScreen extends ConsumerStatefulWidget {
  final String phone;
  const OtpScreen({required this.phone, super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrls = List.generate(6, (_) => TextEditingController());
  final _codeFocuses = List.generate(6, (_) => FocusNode());
  String _currentCode = '';

  @override
  void initState() {
    super.initState();
    if (widget.phone.isNotEmpty) {
      _phoneCtrl.text = widget.phone;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(otpProvider.notifier).sendOtp(widget.phone);
      });
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    for (final c in _codeCtrls) c.dispose();
    for (final f in _codeFocuses) f.dispose();
    super.dispose();
  }

  void _onCodeDigit(int index, String value) {
    if (value.isEmpty) {
      // Backspace: go to previous
      if (index > 0) _codeFocuses[index - 1].requestFocus();
      return;
    }
    // Accept only first digit
    final digit = value.replaceAll(RegExp(r'[^\d]'), '').isNotEmpty
        ? value.replaceAll(RegExp(r'[^\d]'), '')[0]
        : '';
    if (digit.isEmpty) return;

    _codeCtrls[index].text = digit;
    _codeCtrls[index].selection = TextSelection.collapsed(offset: 1);

    // Move to next box
    if (index < 5) {
      _codeFocuses[index + 1].requestFocus();
    } else {
      _codeFocuses[index].unfocus();
    }

    // Collect full code
    final code = _codeCtrls.map((c) => c.text).join();
    setState(() => _currentCode = code);

    if (code.length == 6) {
      _verifyCode(code);
    }
  }

  Future<void> _verifyCode(String code) async {
    final success = await ref.read(otpProvider.notifier).verifyOtp(code);
    if (success && mounted) {
      // Check if onboarding needed
      final session = await ref.read(authRepositoryProvider).loadSession();
      if (session == null) {
        context.go(AppRoutes.onboarding);
      } else {
        await ref.read(sessionProvider.notifier).refresh();
        context.go(AppRoutes.home);
      }
    } else if (mounted) {
      // Clear code on failure
      for (final c in _codeCtrls) c.clear();
      setState(() => _currentCode = '');
      _codeFocuses[0].requestFocus();
      HapticFeedback.heavyImpact();
      // Shake animation via error state
    }
  }

  @override
  Widget build(BuildContext context) {
    final otpState = ref.watch(otpProvider);
    final isCodeStep = otpState.step == OtpStep.enterCode ||
        otpState.step == OtpStep.verifying;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.pagePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xl),

              // ── Logo / Brand ───────────────────────────────────────
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.brand900,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.menu_book_rounded,
                        size: 40,
                        color: AppColors.gold500,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text('منشی', style: AppTypography.urH1),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.xxl),

              if (!isCodeStep)
                _PhoneEntrySection(
                  controller: _phoneCtrl,
                  isSending: otpState.isSending,
                  error: otpState.error,
                  onSend: () {
                    ref
                        .read(otpProvider.notifier)
                        .sendOtp(_phoneCtrl.text.trim());
                  },
                )
              else
                _CodeEntrySection(
                  controllers: _codeCtrls,
                  focuses: _codeFocuses,
                  phone: otpState.phone,
                  isVerifying: otpState.isVerifying,
                  error: otpState.error,
                  resendCooldown: otpState.resendCooldownSeconds,
                  onDigit: _onCodeDigit,
                  onResend: () =>
                      ref.read(otpProvider.notifier).resendOtp(),
                  onVoiceOtp: () =>
                      ref.read(otpProvider.notifier).requestVoiceOtp(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Phone entry ────────────────────────────────────────────────────────────

class _PhoneEntrySection extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final String? error;
  final VoidCallback onSend;

  const _PhoneEntrySection({
    required this.controller,
    required this.isSending,
    required this.error,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'اپنا نمبر درج کریں',
          style: AppTypography.urH2,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.lg),

        // Phone field — big, clear
        TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          style: AppTypography.moneyLarge.copyWith(
            letterSpacing: 2,
          ),
          decoration: InputDecoration(
            hintText: '03xx-xxxxxxx',
            hintStyle: AppTypography.moneyMedium.copyWith(
              color: AppColors.ink300,
            ),
            prefixIcon: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '+92',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ink700,
                ),
              ),
            ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 0, minHeight: 0),
          ),
          onSubmitted: (_) => onSend(),
        ),

        if (error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            error!,
            style: AppTypography.urBody.copyWith(color: AppColors.danger),
            textAlign: TextAlign.center,
          ),
        ],

        const SizedBox(height: AppSpacing.xl),

        ElevatedButton(
          onPressed: isSending ? null : onSend,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 60),
          ),
          child: isSending
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Text('کوڈ بھیجیں', style: AppTypography.urBodyBold),
        ),
      ],
    );
  }
}

// ── Code entry ─────────────────────────────────────────────────────────────

class _CodeEntrySection extends ConsumerWidget {
  final List<TextEditingController> controllers;
  final List<FocusNode> focuses;
  final String phone;
  final bool isVerifying;
  final String? error;
  final int resendCooldown;
  final void Function(int index, String value) onDigit;
  final VoidCallback onResend;
  final VoidCallback onVoiceOtp;

  const _CodeEntrySection({
    required this.controllers,
    required this.focuses,
    required this.phone,
    required this.isVerifying,
    required this.error,
    required this.resendCooldown,
    required this.onDigit,
    required this.onResend,
    required this.onVoiceOtp,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'کوڈ درج کریں',
          style: AppTypography.urH2,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          phone,
          style: AppTypography.moneyMedium.copyWith(color: AppColors.ink500),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        ),
        const SizedBox(height: AppSpacing.xl),

        // 6 big digit boxes
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(6, (i) => _DigitBox(
            controller: controllers[i],
            focusNode: focuses[i],
            onChanged: (v) => onDigit(i, v),
            hasError: error != null,
          )),
        ),

        if (error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            error!,
            style: AppTypography.urBody.copyWith(color: AppColors.danger),
            textAlign: TextAlign.center,
          ),
        ],

        if (isVerifying) ...[
          const SizedBox(height: AppSpacing.lg),
          const Center(child: CircularProgressIndicator()),
        ],

        const SizedBox(height: AppSpacing.xl),

        // Voice OTP option — the key accessibility feature
        // Owner who can't read SMS can get a voice call
        OutlinedButton.icon(
          onPressed: onVoiceOtp,
          icon: const Icon(Icons.phone_rounded, size: 20),
          label: Text(
            'آواز سے کوڈ لیں',
            style: AppTypography.urBodyMedium,
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
          ),
        ),

        const SizedBox(height: AppSpacing.base),

        // Resend
        Center(
          child: TextButton(
            onPressed: resendCooldown > 0 ? null : onResend,
            child: Text(
              resendCooldown > 0
                  ? 'دوبارہ بھیجیں ($resendCooldown)'
                  : 'دوبارہ بھیجیں',
              style: AppTypography.urBody.copyWith(
                color: resendCooldown > 0
                    ? AppColors.ink300
                    : AppColors.brand600,
              ),
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.lg),

        // Help: speak instructions for non-readers
        Center(
          child: GestureDetector(
            onTap: () {
              ref.read(ttsServiceProvider).speak(
                'اپنے فون پر آنے والا چھ ہندسوں کا کوڈ درج کریں۔ '
                'اگر پڑھنا مشکل ہو تو آواز سے کوڈ لیں والا بٹن دبائیں۔',
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.volume_up_rounded,
                  size: 18,
                  color: AppColors.brand600,
                ),
                const SizedBox(width: 6),
                Text(
                  'مدد سنیں',
                  style: AppTypography.urBody.copyWith(
                    color: AppColors.brand600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Single digit box ──────────────────────────────────────────────────────

class _DigitBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final void Function(String) onChanged;
  final bool hasError;

  const _DigitBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.hasError,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 64,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
          border: Border.all(
            color: hasError
                ? AppColors.danger
                : focusNode.hasFocus
                    ? AppColors.brand600
                    : AppColors.ink100,
            width: focusNode.hasFocus ? 2 : 1.5,
          ),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(1),
          ],
          style: AppTypography.numPadDigit.copyWith(fontSize: 28),
          decoration: const InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
