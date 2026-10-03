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
import '../../../widgets/shared/error_state.dart';
import '../../auth/providers/session_provider.dart';
import '../models/payment_models.dart';
import '../repositories/money_repository.dart';
import '../../../widgets/primitives/number_pad.dart';
import '../../../widgets/primitives/method_chips.dart';
import '../../auth/providers/session_provider.dart';
import '../models/payment_models.dart';
import '../repositories/money_repository.dart';

/// Paisa Gaya — the 20-second money-out / expense flow.
class PaisaGayaScreen extends ConsumerStatefulWidget {
  const PaisaGayaScreen({super.key});

  @override
  ConsumerState<PaisaGayaScreen> createState() => _PaisaGayaScreenState();
}

class _PaisaGayaScreenState extends ConsumerState<PaisaGayaScreen> {
  int _amountRs = 0;
  PaymentMethod _method = PaymentMethod.cash;
  ExpenseCategory _category = ExpenseCategory.office;
  bool _saving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permissionServiceProvider);
    if (perms.cannot(Permission.recordPayment)) {
      return Scaffold(
        appBar: AppBar(title: Text('پیسہ گیا', style: AppTypography.urH2)),
        body: const ErrorState(
          messageUr: 'اجازت نہیں',
          speakText: 'آپ کو خرچہ درج کرنے کی اجازت نہیں ہے',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppColors.moneyOut.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_upward_rounded,
                  color: AppColors.moneyOut, size: 18),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text('پیسہ گیا', style: AppTypography.urH2),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Expense category grid — icon-based, no reading
              _ExpenseCategoryGrid(
                selected: _category,
                onChanged: (c) => setState(() => _category = c),
              ),
              const SizedBox(height: AppSpacing.lg),

              NumberPad(
                initialAmount: _amountRs,
                onAmountChanged: (v) => setState(() => _amountRs = v),
              ),
              const SizedBox(height: AppSpacing.lg),

              Text('طریقہ ادائیگی', style: AppTypography.urBodyMedium),
              const SizedBox(height: AppSpacing.sm),
              MethodChips(
                selected: _method,
                onSelected: (m) => setState(() => _method = m),
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
              backgroundColor: AppColors.moneyOut,
            ),
            child: _saving
                ? const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white))
                : Text(
                    _amountRs > 0
                        ? '${formatMoney(_amountRs)} درج کریں'
                        : 'رقم درج کریں',
                    style: AppTypography.urBodyBold,
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
      await ref.read(moneyRepositoryProvider).recordPayment(
        dealerId: session.dealerId,
        kind: PaymentKind.expense,
        amountRs: _amountRs,
        direction: 'out',
        method: _method.dbValue,
        category: _category.dbValue,
        createdBy: session.userId,
      );

      await ref.read(ttsServiceProvider).speak(
        '${_category.labelUr} خرچہ — ${speakAmount(_amountRs)} — ہو گیا',
      );
      HapticFeedback.mediumImpact();
      if (mounted) context.pop();
    } catch (e) {
      setState(() { _saving = false; _error = e.toString(); });
    }
  }
}

class _ExpenseCategoryGrid extends StatelessWidget {
  final ExpenseCategory selected;
  final void Function(ExpenseCategory) onChanged;

  const _ExpenseCategoryGrid({required this.selected, required this.onChanged});

  static const _items = [
    (cat: ExpenseCategory.office,     icon: Icons.business_rounded),
    (cat: ExpenseCategory.fuel,       icon: Icons.local_gas_station_rounded),
    (cat: ExpenseCategory.food,       icon: Icons.restaurant_rounded),
    (cat: ExpenseCategory.listingFee, icon: Icons.campaign_rounded),
    (cat: ExpenseCategory.salary,     icon: Icons.person_rounded),
    (cat: ExpenseCategory.other,      icon: Icons.more_horiz_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      childAspectRatio: 1.4,
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      children: _items.map((item) {
        final isSelected = item.cat == selected;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onChanged(item.cat);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.moneyOut.withAlpha(20)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: AppSpacing.cardRadius,
              border: Border.all(
                color: isSelected ? AppColors.moneyOut : AppColors.ink100,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(item.icon,
                    size: 28,
                    color: isSelected ? AppColors.moneyOut : AppColors.ink500),
                const SizedBox(height: 4),
                Text(
                  item.cat.labelUr,
                  style: AppTypography.urCaption.copyWith(
                    color: isSelected ? AppColors.moneyOut : AppColors.ink700,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
