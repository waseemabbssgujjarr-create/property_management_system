import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/money_formatter.dart';
import 'speak_button.dart';

/// NumberPad — money entry widget.
///
/// Rules (§5.3):
/// - Number pad only (no keyboard)
/// - Live lac/crore readout + 🔊 preview
/// - Quick chips: 1L, 5L, 25L, 1Cr
/// - Backspace to correct
/// - No negative numbers allowed
/// - Internally stores integer rupees
///
/// Usage:
/// ```dart
/// NumberPad(
///   onAmountChanged: (rupees) => setState(() => _amount = rupees),
/// )
/// ```
class NumberPad extends StatefulWidget {
  final void Function(int rupees) onAmountChanged;
  final int? initialAmount;
  final int? maxAmount;

  const NumberPad({
    required this.onAmountChanged,
    this.initialAmount,
    this.maxAmount,
    super.key,
  });

  @override
  State<NumberPad> createState() => _NumberPadState();
}

class _NumberPadState extends State<NumberPad> {
  String _digits = '';

  static const _quickChips = [
    (label: '1 لاکھ',   value: 100000),
    (label: '5 لاکھ',   value: 500000),
    (label: '25 لاکھ',  value: 2500000),
    (label: '1 کروڑ',   value: 10000000),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialAmount != null && widget.initialAmount! > 0) {
      _digits = widget.initialAmount!.toString();
    }
  }

  int get _currentValue => int.tryParse(_digits) ?? 0;

  void _appendDigit(String d) {
    final newDigits = _digits + d;
    final value = int.tryParse(newDigits) ?? 0;
    if (widget.maxAmount != null && value > widget.maxAmount!) return;
    // Max 12 digits (99 crore+)
    if (newDigits.length > 12) return;
    setState(() => _digits = newDigits);
    widget.onAmountChanged(value);
    HapticFeedback.selectionClick();
  }

  void _backspace() {
    if (_digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
    widget.onAmountChanged(_currentValue);
    HapticFeedback.selectionClick();
  }

  void _clearAll() {
    if (_digits.isEmpty) return;
    setState(() => _digits = '');
    widget.onAmountChanged(0);
    HapticFeedback.heavyImpact();
  }

  void _setChip(int value) {
    setState(() => _digits = value.toString());
    widget.onAmountChanged(value);
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final displayAmount = _currentValue;
    final formatted = displayAmount > 0
        ? formatMoney(displayAmount)
        : '₨ 0';
    final spokenText = displayAmount > 0
        ? speakAmount(displayAmount)
        : 'صفر روپے';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Amount preview ───────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: AppSpacing.cardRadius,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  formatted,
                  style: AppTypography.numPadPreview.copyWith(
                    color: displayAmount > 0
                        ? AppColors.moneyIn
                        : Theme.of(context).colorScheme.onSurface.withAlpha(80),
                  ),
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SpeakButton(
                text: spokenText,
                size: SpeakButtonSize.medium,
                color: AppColors.brand600,
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // ── Quick chips ──────────────────────────────────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
          child: Row(
            children: _quickChips.map((chip) {
              return Padding(
                padding: const EdgeInsets.only(left: AppSpacing.sm),
                child: ActionChip(
                  label: Text(
                    chip.label,
                    style: AppTypography.urLabel.copyWith(
                      color: AppColors.brand600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: () => _setChip(chip.value),
                  backgroundColor: AppColors.brand100,
                  side: BorderSide(color: AppColors.brand600.withAlpha(50)),
                  padding: AppSpacing.chipPadding,
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // ── Number grid ──────────────────────────────────────────────
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          childAspectRatio: 1.8,
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
          children: [
            ...[1, 2, 3, 4, 5, 6, 7, 8, 9].map(
              (d) => _NumKey(digit: '$d', onTap: () => _appendDigit('$d')),
            ),
            _NumKey(digit: '0', onTap: () => _appendDigit('0')),
            _NumKey(
              digit: '00',
              onTap: () {
                _appendDigit('0');
                _appendDigit('0');
              },
            ),
            _BackspaceKey(onTap: _backspace, onLongPress: _clearAll),
          ],
        ),
      ],
    );
  }
}

class _NumKey extends StatelessWidget {
  final String digit;
  final VoidCallback onTap;

  const _NumKey({required this.digit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
          ),
          child: Text(
            digit,
            style: AppTypography.numPadDigit.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _BackspaceKey extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _BackspaceKey({required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer.withAlpha(80),
            borderRadius: BorderRadius.circular(AppSpacing.radiusButton),
          ),
          child: Icon(
            Icons.backspace_outlined,
            size: 22,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ),
    );
  }
}
