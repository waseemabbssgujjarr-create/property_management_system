import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../widgets/primitives/speak_button.dart';
import '../../../widgets/shared/skeleton_loader.dart';
import '../../auth/providers/session_provider.dart';
import '../models/payment_models.dart';
import '../repositories/money_repository.dart';

/// Receipts — numbered Urdu receipt cards, shareable.
class ReceiptsScreen extends ConsumerWidget {
  const ReceiptsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    final paymentsAsync = ref.watch(_receiptsProvider(session?.dealerId ?? ''));

    return Scaffold(
      appBar: AppBar(
        title: Text('رسیدیں', style: AppTypography.urH2),
      ),
      body: paymentsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.base),
          child: ListSkeleton(itemCount: 5, itemHeight: 120),
        ),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (payments) {
          final receipts = payments.where((p) => p.receiptNo != null).toList();
          if (receipts.isEmpty) {
            return const Center(
              child: Text('کوئی رسید نہیں', style: TextStyle(fontFamily: 'NotoNaskhArabic')),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.base),
            itemCount: receipts.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.base),
            itemBuilder: (_, i) => _ReceiptCard(payment: receipts[i]),
          );
        },
      ),
    );
  }
}

final _receiptsProvider = FutureProvider.family<List<Payment>, String>(
  (ref, dealerId) async {
    if (dealerId.isEmpty) return [];
    return ref.read(moneyRepositoryProvider).getPayments(
      dealerId: dealerId,
      limit: 30,
    );
  },
);

/// ReceiptCard — stamp-style, premium, shareable.
class _ReceiptCard extends StatelessWidget {
  final Payment payment;
  const _ReceiptCard({required this.payment});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: AppSpacing.cardRadius,
        border: Border.all(color: AppColors.ink100),
        boxShadow: AppElevation.medium,
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(AppSpacing.base),
            decoration: BoxDecoration(
              color: AppColors.brand900,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppSpacing.radiusCard)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'رسید #${payment.receiptNo}',
                  style: AppTypography.moneySmall.copyWith(color: Colors.white),
                  textDirection: TextDirection.ltr,
                ),
                Text(
                  payment.kind.labelUr,
                  style: AppTypography.urCaption.copyWith(color: AppColors.gold500),
                ),
              ],
            ),
          ),

          // Perforated divider
          _PerforatedDivider(),

          // Amount — the hero
          Padding(
            padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.lg, horizontal: AppSpacing.base),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  formatMoney(payment.amountRs),
                  style: AppTypography.moneyHero.copyWith(
                    color: payment.isIncoming
                        ? AppColors.moneyIn
                        : AppColors.moneyOut,
                    fontSize: 36,
                  ),
                  textDirection: TextDirection.ltr,
                ),
                const SizedBox(width: AppSpacing.sm),
                SpeakButton(
                  text: speakAmount(payment.amountRs),
                  size: SpeakButtonSize.large,
                  color: AppColors.brand600,
                ),
              ],
            ),
          ),

          // Footer details
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.base, 0, AppSpacing.base, AppSpacing.base),
            child: Column(
              children: [
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${payment.occurredAt.day}/'
                      '${payment.occurredAt.month}/'
                      '${payment.occurredAt.year}',
                      style: AppTypography.caption,
                      textDirection: TextDirection.ltr,
                    ),
                    if (payment.method != null)
                      Text(
                        _methodLabel(payment.method!),
                        style: AppTypography.urCaption,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _methodLabel(String m) => switch (m) {
    'cash'      => 'نقد',
    'bank'      => 'بینک',
    'jazzcash'  => 'جاز کیش',
    'easypaisa' => 'ایزی پیسہ',
    _           => m,
  };
}

class _PerforatedDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: Row(
        children: [
          Container(width: 8, height: 16, color: Theme.of(context).colorScheme.surface),
          Expanded(
            child: LayoutBuilder(
              builder: (_, constraints) {
                final dotCount = (constraints.maxWidth / 10).floor();
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(
                    dotCount,
                    (_) => Container(
                      width: 4, height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.ink100,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(width: 8, height: 16, color: Theme.of(context).colorScheme.surface),
        ],
      ),
    );
  }
}
