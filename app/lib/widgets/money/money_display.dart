import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/money_formatter.dart';
import '../primitives/speak_button.dart';

/// MoneyDisplay — shows a formatted lac/crore amount with a speak button.
///
/// Rules:
/// - Always lac/crore format for amounts ≥ 1 lac
/// - IN amounts = green, OUT amounts = red
/// - Every money figure gets 🔊
/// - Money figures minimum 24sp on owner-facing screens
enum MoneyDisplaySize { small, medium, large, hero }

enum MoneyDirection { in_, out_, neutral }

class MoneyDisplay extends StatelessWidget {
  final int rupees;
  final MoneyDirection direction;
  final MoneyDisplaySize size;
  final bool showSpeakButton;
  final String? label;

  const MoneyDisplay({
    required this.rupees,
    this.direction = MoneyDirection.neutral,
    this.size = MoneyDisplaySize.medium,
    this.showSpeakButton = true,
    this.label,
    super.key,
  });

  Color get _color => switch (direction) {
    MoneyDirection.in_     => AppColors.moneyIn,
    MoneyDirection.out_    => AppColors.moneyOut,
    MoneyDirection.neutral => AppColors.ink900,
  };

  TextStyle get _style => switch (size) {
    MoneyDisplaySize.small  => AppTypography.moneySmall,
    MoneyDisplaySize.medium => AppTypography.moneyMedium,
    MoneyDisplaySize.large  => AppTypography.moneyLarge,
    MoneyDisplaySize.hero   => AppTypography.moneyHero,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: AppTypography.urCaption.copyWith(color: AppColors.ink500),
          ),
          const SizedBox(height: 2),
        ],
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              formatMoney(rupees),
              style: _style.copyWith(color: _color),
              textDirection: TextDirection.ltr,
            ),
            if (showSpeakButton) ...[
              const SizedBox(width: 6),
              SpeakButton(
                text: speakAmount(rupees),
                size: size == MoneyDisplaySize.hero
                    ? SpeakButtonSize.large
                    : size == MoneyDisplaySize.large
                        ? SpeakButtonSize.medium
                        : SpeakButtonSize.small,
                color: _color.withAlpha(180),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
