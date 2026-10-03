import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../primitives/speak_button.dart';

/// Error state widget.
///
/// Rules (§6.4):
/// - icon + 3-word Urdu + voice option + retry button
/// - No dead buttons, no silent failures, no paragraphs
/// - Every async action has: idle → loading → success → error
class ErrorState extends StatelessWidget {
  final String messageUr;
  final VoidCallback? onRetry;
  final String? speakText;

  const ErrorState({
    required this.messageUr,
    this.onRetry,
    this.speakText,
    super.key,
  });

  factory ErrorState.network({VoidCallback? onRetry}) => ErrorState(
    messageUr: 'انٹرنیٹ نہیں ہے',
    speakText: 'انٹرنیٹ کنیکشن درست کریں اور دوبارہ کوشش کریں',
    onRetry: onRetry,
  );

  factory ErrorState.generic({VoidCallback? onRetry}) => ErrorState(
    messageUr: 'کچھ غلط ہوا',
    speakText: 'کوئی مسئلہ آیا — دوبارہ کوشش کریں',
    onRetry: onRetry,
  );

  factory ErrorState.notFound() => const ErrorState(
    messageUr: 'نہیں ملا',
  );

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.danger.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 36,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              messageUr,
              style: AppTypography.urH2.copyWith(color: AppColors.ink700),
              textAlign: TextAlign.center,
            ),
            if (speakText != null) ...[
              const SizedBox(height: AppSpacing.sm),
              SpeakButton(
                text: speakText!,
                size: SpeakButtonSize.medium,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text('دوبارہ کوشش', style: AppTypography.urBodyMedium),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
