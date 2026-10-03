import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../primitives/speak_button.dart';

/// EmptyState — illustration + one big CTA + optional voice explanation.
/// Never a blank screen, never a paragraph of text.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String messageUr;
  final String? ctaLabelUr;
  final VoidCallback? onCtaTap;
  final String? speakText;

  const EmptyState({
    required this.icon,
    required this.messageUr,
    this.ctaLabelUr,
    this.onCtaTap,
    this.speakText,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.brand100,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: AppColors.brand600),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              messageUr,
              style: AppTypography.urH2.copyWith(color: AppColors.ink500),
              textAlign: TextAlign.center,
            ),
            if (speakText != null) ...[
              const SizedBox(height: AppSpacing.sm),
              SpeakButton(
                text: speakText!,
                size: SpeakButtonSize.large,
              ),
            ],
            if (ctaLabelUr != null && onCtaTap != null) ...[
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton.icon(
                onPressed: onCtaTap,
                icon: const Icon(Icons.add_rounded),
                label: Text(ctaLabelUr!, style: AppTypography.urBodyMedium),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
