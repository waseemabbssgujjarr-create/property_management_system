import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../widgets/deal/stage_strip.dart';
import '../../../widgets/shared/empty_state.dart';
import '../../../widgets/shared/error_state.dart';
import '../../../widgets/shared/skeleton_loader.dart';
import '../models/deal_models.dart';
import '../providers/deals_provider.dart';

/// Deals list screen — cards with stage color badge, days in stage,
/// stale-deal highlighting (>7 days glows), mic search.
class DealsScreen extends ConsumerStatefulWidget {
  const DealsScreen({super.key});

  @override
  ConsumerState<DealsScreen> createState() => _DealsScreenState();
}

class _DealsScreenState extends ConsumerState<DealsScreen> {
  DealStage? _filter;

  @override
  Widget build(BuildContext context) {
    final dealsAsync = ref.watch(dealsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('ڈیلز', style: AppTypography.urH2),
        actions: [
          IconButton(
            onPressed: () => context.go(AppRoutes.search),
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            onPressed: () => context.push(AppRoutes.nayaDeal),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: _StageFilterBar(
            current: _filter,
            onChanged: (s) {
              setState(() => _filter = s);
              ref.read(dealsProvider.notifier).filterByStage(s);
            },
          ),
        ),
      ),
      body: dealsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.base),
          child: ListSkeleton(itemCount: 5, itemHeight: 90),
        ),
        error: (e, _) => ErrorState.generic(
          onRetry: () => ref.read(dealsProvider.notifier).refresh(),
        ),
        data: (deals) => deals.isEmpty
            ? EmptyState(
                icon: Icons.handshake_rounded,
                messageUr: 'کوئی ڈیل نہیں',
                ctaLabelUr: 'نیا ڈیل',
                onCtaTap: () => context.push(AppRoutes.nayaDeal),
                speakText: 'کوئی ڈیل نہیں — نیا ڈیل شروع کریں',
              )
            : RefreshIndicator(
                color: AppColors.brand600,
                onRefresh: () => ref.read(dealsProvider.notifier).refresh(),
                child: ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.base),
                  itemCount: deals.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, i) => _DealCard(deal: deals[i]),
                ),
              ),
      ),
    );
  }
}

class _StageFilterBar extends StatelessWidget {
  final DealStage? current;
  final void Function(DealStage?) onChanged;

  const _StageFilterBar({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      child: Row(
        children: [
          _FilterChip(
            label: 'سب',
            active: current == null,
            color: AppColors.brand600,
            onTap: () => onChanged(null),
          ),
          const SizedBox(width: AppSpacing.xs),
          ...DealStage.values.where((s) => !s.isTerminal).map((s) =>
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: _FilterChip(
                label: s.labelUr,
                active: current == s,
                color: s.color,
                onTap: () => onChanged(s),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: active ? color : color.withAlpha(20),
          borderRadius: AppSpacing.pillRadius,
          border: Border.all(color: color.withAlpha(active ? 255 : 80)),
        ),
        child: Text(
          label,
          style: AppTypography.urCaption.copyWith(
            color: active ? Colors.white : color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _DealCard extends StatelessWidget {
  final Deal deal;
  const _DealCard({required this.deal});

  @override
  Widget build(BuildContext context) {
    final stage = deal.stage;
    final isStale = deal.isStale;
    final tokenUrgent = deal.tokenUrgent;

    return GestureDetector(
      onTap: () => context.push('${AppRoutes.deals}/${deal.id}'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: isStale
              ? AppColors.warn.withAlpha(15)
              : tokenUrgent
                  ? AppColors.danger.withAlpha(10)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: AppSpacing.cardRadius,
          border: Border.all(
            color: isStale
                ? AppColors.warn.withAlpha(80)
                : tokenUrgent
                    ? AppColors.danger.withAlpha(80)
                    : stage.color.withAlpha(40),
            width: isStale || tokenUrgent ? 1.5 : 1,
          ),
          boxShadow: AppElevation.low,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stage badge + days + expiry
            Row(
              children: [
                _StageBadge(stage: stage),
                const SizedBox(width: AppSpacing.sm),
                if (deal.daysInStage > 0)
                  Text(
                    '${deal.daysInStage} دن',
                    style: AppTypography.caption.copyWith(
                      color: isStale ? AppColors.warn : AppColors.ink300,
                    ),
                  ),
                const Spacer(),
                if (tokenUrgent && deal.tokenDaysRemaining != null)
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined,
                          size: 14, color: AppColors.danger),
                      const SizedBox(width: 3),
                      Text(
                        '${deal.tokenDaysRemaining} دن',
                        style: AppTypography.caption
                            .copyWith(color: AppColors.danger),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Property / buyer info
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deal.buyerPartyId != null ? 'خریدار' : 'انکوائری',
                        style: AppTypography.caption,
                      ),
                      if (deal.dealPriceRs != null)
                        Text(
                          formatMoney(deal.dealPriceRs!),
                          style: AppTypography.moneyMedium.copyWith(
                            color: AppColors.brand600,
                          ),
                          textDirection: TextDirection.ltr,
                        ),
                    ],
                  ),
                ),
                if (deal.expectedCommRs != null && deal.expectedCommRs! > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('کمیشن', style: AppTypography.caption),
                      Text(
                        formatMoney(deal.expectedCommRs!),
                        style: AppTypography.moneySmall.copyWith(
                          color: AppColors.success,
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                    ],
                  ),
              ],
            ),
            // Stale warning
            if (isStale)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 14, color: AppColors.warn),
                    const SizedBox(width: 4),
                    Text(
                      '${deal.daysInStage} دن سے رکا ہے',
                      style: AppTypography.caption
                          .copyWith(color: AppColors.warn),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StageBadge extends StatelessWidget {
  final DealStage stage;
  const _StageBadge({required this.stage});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: stage.color.withAlpha(25),
        borderRadius: AppSpacing.pillRadius,
        border: Border.all(color: stage.color.withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(stage.icon, size: 13, color: stage.color),
          const SizedBox(width: 4),
          Text(
            stage.labelUr,
            style: AppTypography.urCaption.copyWith(
              color: stage.color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
