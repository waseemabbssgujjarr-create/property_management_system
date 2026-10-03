import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../widgets/deal/stage_strip.dart';
import '../../../widgets/shared/error_state.dart';
import '../../../widgets/shared/skeleton_loader.dart';
import '../models/deal_models.dart';
import '../providers/deals_provider.dart';

/// Deal detail — visual timeline (icons + colors), parties, commission splits,
/// payments log, stage advancement.
class DealDetailScreen extends ConsumerWidget {
  final String dealId;
  const DealDetailScreen({required this.dealId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dealAsync = ref.watch(dealDetailProvider(dealId));

    return Scaffold(
      appBar: AppBar(
        title: Text('ڈیل', style: AppTypography.urH2),
      ),
      body: dealAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.base),
          child: ListSkeleton(itemCount: 6),
        ),
        error: (e, _) => ErrorState.generic(
          onRetry: () => ref.invalidate(dealDetailProvider(dealId)),
        ),
        data: (deal) => _DealDetailBody(deal: deal),
      ),
    );
  }
}

class _DealDetailBody extends ConsumerWidget {
  final Deal deal;
  const _DealDetailBody({required this.deal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Stage strip
          StageStrip(currentStage: deal.stage),
          const SizedBox(height: AppSpacing.lg),

          // Deal financials card
          _FinancialsCard(deal: deal),
          const SizedBox(height: AppSpacing.base),

          // Token details (if in token stage+)
          if (deal.tokenRs != null) _TokenCard(deal: deal),
          if (deal.tokenRs != null) const SizedBox(height: AppSpacing.base),

          // Bayana details
          if (deal.bayanaRs != null) _BayanaCard(deal: deal),
          if (deal.bayanaRs != null) const SizedBox(height: AppSpacing.base),

          // Commission splits
          _SplitsSection(dealId: deal.id, expectedCommRs: deal.expectedCommRs ?? 0),
          const SizedBox(height: AppSpacing.base),

          // Stage advance button
          if (!deal.stage.isTerminal)
            _StageAdvanceSection(deal: deal),

          const SizedBox(height: AppSpacing.xl),

          // Events timeline
          _EventsTimeline(dealId: deal.id),
        ],
      ),
    );
  }
}

class _FinancialsCard extends StatelessWidget {
  final Deal deal;
  const _FinancialsCard({required this.deal});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: AppSpacing.cardRadius,
      ),
      child: Column(
        children: [
          _Row('ڈیل قیمت', deal.dealPriceRs != null ? formatMoney(deal.dealPriceRs!) : '—'),
          if (deal.expectedCommRs != null)
            _Row('متوقع کمیشن', formatMoney(deal.expectedCommRs!),
                valueColor: AppColors.success),
          _Row('کمیشن %',
              '${deal.commBuyerPct.toStringAsFixed(1)}% + ${deal.commSellerPct.toStringAsFixed(1)}%'),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _Row(this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.urBody.copyWith(color: AppColors.ink500)),
          Text(
            value,
            style: AppTypography.moneySmall.copyWith(
              color: valueColor ?? AppColors.ink900,
            ),
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    );
  }
}

class _TokenCard extends StatelessWidget {
  final Deal deal;
  const _TokenCard({required this.deal});

  @override
  Widget build(BuildContext context) {
    final daysLeft = deal.tokenDaysRemaining;
    final isUrgent = deal.tokenUrgent;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: isUrgent ? AppColors.danger.withAlpha(15) : AppColors.stageToken.withAlpha(15),
        borderRadius: AppSpacing.cardRadius,
        border: Border.all(
          color: isUrgent ? AppColors.danger.withAlpha(80) : AppColors.stageToken.withAlpha(80),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.handshake_rounded,
                  color: isUrgent ? AppColors.danger : AppColors.stageToken),
              const SizedBox(width: AppSpacing.sm),
              Text(deal.tokenType?.labelUr ?? 'ٹوکن',
                  style: AppTypography.urBodyBold.copyWith(
                    color: isUrgent ? AppColors.danger : AppColors.stageToken,
                  )),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _Row('ٹوکن رقم', deal.tokenRs != null ? formatMoney(deal.tokenRs!) : '—'),
          if (daysLeft != null)
            _Row(
              'باقی دن',
              '$daysLeft دن',
              valueColor: isUrgent ? AppColors.danger : null,
            ),
          if (deal.tokenTermsText != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                deal.tokenTermsText!,
                style: AppTypography.urBody.copyWith(color: AppColors.ink500),
                textDirection: TextDirection.rtl,
              ),
            ),
        ],
      ),
    );
  }
}

class _BayanaCard extends StatelessWidget {
  final Deal deal;
  const _BayanaCard({required this.deal});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.stageBayana.withAlpha(15),
        borderRadius: AppSpacing.cardRadius,
        border: Border.all(color: AppColors.stageBayana.withAlpha(80)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.description_rounded, color: AppColors.stageBayana),
              const SizedBox(width: AppSpacing.sm),
              Text('بیعانہ', style: AppTypography.urBodyBold.copyWith(color: AppColors.stageBayana)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _Row('بیعانہ رقم', deal.bayanaRs != null ? formatMoney(deal.bayanaRs!) : '—'),
          if (deal.bayanaDueAt != null)
            _Row('آخری تاریخ',
                '${deal.bayanaDueAt!.day}/${deal.bayanaDueAt!.month}/${deal.bayanaDueAt!.year}'),
        ],
      ),
    );
  }
}

class _SplitsSection extends ConsumerWidget {
  final String dealId;
  final int expectedCommRs;

  const _SplitsSection({required this.dealId, required this.expectedCommRs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final splitsAsync = ref.watch(dealSplitsProvider(dealId));

    return splitsAsync.when(
      loading: () => const CardSkeleton(height: 60),
      error: (_, __) => const SizedBox.shrink(),
      data: (splits) {
        if (splits.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('کمیشن حصے', style: AppTypography.urBodyBold),
            const SizedBox(height: AppSpacing.sm),
            ...splits.map((s) {
              final earned = ((expectedCommRs * s.pct) / 100).round();
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${s.pct.toStringAsFixed(0)}%',
                          style: AppTypography.urBody),
                    ),
                    Text(formatMoney(earned),
                        style: AppTypography.moneySmall.copyWith(color: AppColors.success),
                        textDirection: TextDirection.ltr),
                    const SizedBox(width: AppSpacing.sm),
                    Text('ادا: ${formatMoney(s.paidRs)}',
                        style: AppTypography.caption,
                        textDirection: TextDirection.ltr),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _StageAdvanceSection extends ConsumerWidget {
  final Deal deal;
  const _StageAdvanceSection({required this.deal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nextStages = deal.stage.nextStages
        .where((s) => s != DealStage.lost)
        .toList();

    if (nextStages.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('اگلا مرحلہ', style: AppTypography.urBodyBold),
        const SizedBox(height: AppSpacing.sm),
        ...nextStages.map((next) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: ElevatedButton.icon(
            onPressed: () => _advance(context, ref, next),
            icon: Icon(next.icon),
            label: Text(next.labelUr, style: AppTypography.urBodyMedium),
            style: ElevatedButton.styleFrom(
              backgroundColor: next.color,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
            ),
          ),
        )),
        OutlinedButton(
          onPressed: () => _markLost(context, ref),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.stageLost,
            side: const BorderSide(color: AppColors.stageLost),
          ),
          child: Text('ڈیل ختم', style: AppTypography.urBodyMedium),
        ),
      ],
    );
  }

  Future<void> _advance(BuildContext context, WidgetRef ref, DealStage next) async {
    try {
      await ref.read(dealsProvider.notifier).advanceStage(
        deal.id, deal.stage, next,
      );
      ref.invalidate(dealDetailProvider(deal.id));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _markLost(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(dealsProvider.notifier).advanceStage(
        deal.id, deal.stage, DealStage.lost,
        stageData: {'lost_reason': 'other'},
      );
      ref.invalidate(dealDetailProvider(deal.id));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.danger),
        );
      }
    }
  }
}

class _EventsTimeline extends ConsumerWidget {
  final String dealId;
  const _EventsTimeline({required this.dealId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(dealEventsProvider(dealId));

    return eventsAsync.when(
      loading: () => const CardSkeleton(height: 80),
      error: (_, __) => const SizedBox.shrink(),
      data: (events) {
        if (events.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ڈیل کی تاریخ', style: AppTypography.urBodyBold),
            const SizedBox(height: AppSpacing.sm),
            ...events.reversed.take(5).map((e) => _EventRow(event: e)),
          ],
        );
      },
    );
  }
}

class _EventRow extends StatelessWidget {
  final DealEvent event;
  const _EventRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final stage = DealStage.fromDb(event.toStage);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            margin: const EdgeInsets.only(right: 12, top: 6),
            decoration: BoxDecoration(
              color: stage?.color ?? AppColors.ink300,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              stage?.labelUr ?? event.kind,
              style: AppTypography.urBody,
            ),
          ),
          Text(
            '${event.occurredAt.day}/${event.occurredAt.month}',
            style: AppTypography.caption,
          ),
        ],
      ),
    );
  }
}
