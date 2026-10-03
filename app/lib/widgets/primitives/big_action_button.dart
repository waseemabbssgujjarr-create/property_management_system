import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import 'pressable.dart';
import 'speak_button.dart';

/// BigActionButton — the 3 home screen action buttons.
///
/// Rules (§5.3):
/// - 96dp minimum
/// - Icon + 2-word Urdu label
/// - Press scale 0.97 (via Pressable)
/// - Press-and-hold speaks label
/// - States: default / pressed / loading / disabled
///
/// Used for:
/// 💰 Paisa Aya (money in, green)
/// 💸 Paisa Gaya (money out, red)
/// ➕ Naya Deal (new deal, brand green)
class BigActionButton extends StatelessWidget {
  final IconData icon;
  final String labelUr;
  final Color color;
  final VoidCallback? onTap;
  final bool isLoading;
  final bool enabled;

  const BigActionButton({
    required this.icon,
    required this.labelUr,
    required this.color,
    this.onTap,
    this.isLoading = false,
    this.enabled = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SpeakOnHold(
      text: labelUr,
      child: Pressable(
        onTap: enabled && !isLoading ? onTap : null,
        speakLabel: labelUr,
        haptic: true,
        enabled: enabled && !isLoading,
        child: Container(
          width: AppSpacing.homeButtonSize,
          height: AppSpacing.homeButtonSize,
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
            border: Border.all(
              color: color.withAlpha(60),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withAlpha(30),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: isLoading
                    ? SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: color,
                        ),
                      )
                    : Icon(icon, size: 36, color: color),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                labelUr,
                style: AppTypography.urBodyMedium.copyWith(
                  color: color,
                  fontSize: 13,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
