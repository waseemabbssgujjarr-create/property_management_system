import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// Payment method selector as logo chips (visual, no reading required).
///
/// Methods: Cash / Bank / JazzCash / Easypaisa
/// Each shown as a colored icon chip — zero reading needed.
enum PaymentMethod { cash, bank, jazzcash, easypaisa }

extension PaymentMethodExt on PaymentMethod {
  String get dbValue => switch (this) {
    PaymentMethod.cash      => 'cash',
    PaymentMethod.bank      => 'bank',
    PaymentMethod.jazzcash  => 'jazzcash',
    PaymentMethod.easypaisa => 'easypaisa',
  };

  String get labelUr => switch (this) {
    PaymentMethod.cash      => 'نقد',
    PaymentMethod.bank      => 'بینک',
    PaymentMethod.jazzcash  => 'جاز کیش',
    PaymentMethod.easypaisa => 'ایزی پیسہ',
  };

  String get labelEn => switch (this) {
    PaymentMethod.cash      => 'Cash',
    PaymentMethod.bank      => 'Bank',
    PaymentMethod.jazzcash  => 'JazzCash',
    PaymentMethod.easypaisa => 'Easypaisa',
  };

  IconData get icon => switch (this) {
    PaymentMethod.cash      => Icons.payments_rounded,
    PaymentMethod.bank      => Icons.account_balance_rounded,
    PaymentMethod.jazzcash  => Icons.phone_android_rounded,
    PaymentMethod.easypaisa => Icons.phone_android_rounded,
  };

  Color get color => switch (this) {
    PaymentMethod.cash      => AppColors.success,
    PaymentMethod.bank      => AppColors.brand600,
    PaymentMethod.jazzcash  => const Color(0xFF2C5F2E), // JazzCash green
    PaymentMethod.easypaisa => const Color(0xFF5D4037), // Easypaisa brown
  };

  static PaymentMethod? fromDb(String? value) => switch (value) {
    'cash'      => PaymentMethod.cash,
    'bank'      => PaymentMethod.bank,
    'jazzcash'  => PaymentMethod.jazzcash,
    'easypaisa' => PaymentMethod.easypaisa,
    _           => null,
  };
}

/// MethodChips — select payment method visually.
class MethodChips extends StatelessWidget {
  final PaymentMethod? selected;
  final void Function(PaymentMethod method) onSelected;

  const MethodChips({
    required this.onSelected,
    this.selected,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: PaymentMethod.values.map((method) {
        final isSelected = selected == method;
        return _MethodChip(
          method: method,
          isSelected: isSelected,
          onTap: () {
            HapticFeedback.selectionClick();
            onSelected(method);
          },
        );
      }).toList(),
    );
  }
}

class _MethodChip extends StatelessWidget {
  final PaymentMethod method;
  final bool isSelected;
  final VoidCallback onTap;

  const _MethodChip({
    required this.method,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? method.color.withAlpha(30)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: AppSpacing.pillRadius,
          border: Border.all(
            color: isSelected ? method.color : AppColors.ink100,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              method.icon,
              size: 18,
              color: isSelected ? method.color : AppColors.ink500,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              method.labelUr,
              style: AppTypography.urLabel.copyWith(
                color: isSelected ? method.color : AppColors.ink500,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
