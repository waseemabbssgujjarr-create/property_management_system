import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/services/tts_service.dart';
import '../../../core/services/permission_service.dart';
import '../../../widgets/primitives/number_pad.dart';
import '../../../widgets/primitives/method_chips.dart';
import '../../../widgets/primitives/photo_capture.dart';
import '../../../widgets/shared/error_state.dart';
import '../../auth/providers/session_provider.dart';
import '../models/payment_models.dart';
import '../repositories/money_repository.dart';

/// Paisa Aya — the 20-second money-in flow.
///
/// Flow: pick deal (photo cards) → NumberPad → method chips →
///       optional receipt photo → confirm → spoken confirmation
class PaisaAyaScreen extends ConsumerStatefulWidget {
  const PaisaAyaScreen({super.key});

  @override
  ConsumerState<PaisaAyaScreen> createState() => _PaisaAyaScreenState();
}

class _PaisaAyaScreenState extends ConsumerState<PaisaAyaScreen> {
  int _amountRs = 0;
  PaymentMethod _method = PaymentMethod.cash;
  PaymentKind _kind = PaymentKind.commissionIn;
  String? _receiptPhotoPath;
  bool _saving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    // Permission check — agent role cannot record payments
    final perms = ref.watch(permissionServiceProvider);
    if (perms.cannot(Permission.recordPayment)) {
      return Scaffold(
        appBar: AppBar(title: Text('پیسہ آیا', style: AppTypography.urH2)),
        body: const ErrorState(
          messageUr: 'اجازت نہیں',
          speakText: 'آپ کو ادائیگی درج کرنے کی اجازت نہیں ہے',
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppColors.moneyIn.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_downward_rounded,
                  color: AppColors.moneyIn, size: 18),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text('پیسہ آیا', style: AppTypography.urH2),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Kind selector (token/bayana/commission/other)
              _KindSelector(
                selected: _kind,
                onChanged: (k) => setState(() => _kind = k),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Number pad
              NumberPad(
                initialAmount: _amountRs,
                onAmountChanged: (v) => setState(() => _amountRs = v),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Payment method chips
              Text('طریقہ ادائیگی', style: AppTypography.urBodyMedium),
              const SizedBox(height: AppSpacing.sm),
              MethodChips(
                selected: _method,
                onSelected: (m) => setState(() => _method = m),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Receipt photo (optional)
              Text('رسید کا فوٹو (اختیاری)', style: AppTypography.urBodyMedium),
              const SizedBox(height: AppSpacing.sm),
              PhotoCapture(
                labelUr: 'رسید کا فوٹو لیں',
                onPhotoCaptured: (path) =>
                    setState(() => _receiptPhotoPath = path),
              ),

              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: AppTypography.urBody.copyWith(color: AppColors.danger),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: ElevatedButton(
            onPressed: _amountRs > 0 && !_saving ? _record : null,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 60),
              backgroundColor: AppColors.moneyIn,
            ),
            child: _saving
                ? const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, size: 22),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        _amountRs > 0
                            ? '${formatMoney(_amountRs)} محفوظ کریں'
                            : 'رقم درج کریں',
                        style: AppTypography.urBodyBold,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _record() async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return;

    setState(() { _saving = true; _error = null; });
    try {
      final payment = await ref.read(moneyRepositoryProvider).recordPayment(
        dealerId: session.dealerId,
        kind: _kind,
        amountRs: _amountRs,
        direction: 'in',
        method: _method.dbValue,
        generateReceipt: true,
        createdBy: session.userId,
      );

      // Spoken confirmation — the trust moment for non-readers
      final spoken = '${_kind.labelUr} — ${speakAmount(_amountRs)} — ہو گیا';
      await ref.read(ttsServiceProvider).speak(spoken);
      HapticFeedback.heavyImpact();

      if (mounted) context.pop();
    } catch (e) {
      setState(() { _saving = false; _error = e.toString(); });
    }
  }
}

class _KindSelector extends StatelessWidget {
  final PaymentKind selected;
  final void Function(PaymentKind) onChanged;

  const _KindSelector({required this.selected, required this.onChanged});

  static const _moneyInKinds = [
    PaymentKind.tokenIn,
    PaymentKind.bayanaIn,
    PaymentKind.commissionIn,
    PaymentKind.otherIn,
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      children: _moneyInKinds.map((k) {
        final active = k == selected;
        return GestureDetector(
          onTap: () => onChanged(k),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: active ? AppColors.moneyIn.withAlpha(20) : Colors.transparent,
              borderRadius: AppSpacing.pillRadius,
              border: Border.all(
                color: active ? AppColors.moneyIn : AppColors.ink100,
                width: active ? 2 : 1,
              ),
            ),
            child: Text(
              k.labelUr,
              style: AppTypography.urLabel.copyWith(
                color: active ? AppColors.moneyIn : AppColors.ink500,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
