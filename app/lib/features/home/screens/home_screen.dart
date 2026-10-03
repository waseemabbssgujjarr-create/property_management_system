import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/state/app_mode.dart';
import '../../../core/services/tts_service.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../widgets/primitives/big_action_button.dart';
import '../../../widgets/deal/stage_strip.dart';
import '../../../widgets/money/money_display.dart';
import '../../../widgets/shared/skeleton_loader.dart';
import '../../../widgets/shared/error_state.dart';
import '../../auth/providers/session_provider.dart';
import '../providers/dashboard_provider.dart';
import '../models/dashboard_models.dart';

/// Home Screen — "Aaj ka Hisaab" (Today's Account)
///
/// Simple Mode (default for owner):
/// ┌────────────────────────────────────┐
/// │  آج کا حساب          🔔 🔍        │
/// │                                    │
/// │  ₨ 8 لاکھ 🔊   (expected comm)    │
/// │                                    │
/// │  [💰 پیسہ آیا] [💸 پیسہ گیا] [➕ نیا ڈیل] │
/// │                                    │
/// │  🟡 ٹوکن (3)  🔵 بیعانہ (1) ...  │
/// │                                    │
/// │  ⚠️ ٹوکن ختم ہونے والے (2)        │
/// │  📞 آج کے فالو اپ (4)             │
/// └────────────────────────────────────┘
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _countUpCtrl;

  @override
  void initState() {
    super.initState();
    _countUpCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  @override
  void dispose() {
    _countUpCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(appModeSyncProvider);
    final session = ref.watch(currentSessionProvider);
    final dashAsync = ref.watch(dashboardProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.brand600,
          onRefresh: () => ref.read(dashboardProvider.notifier).refresh(),
          child: CustomScrollView(
            slivers: [
              // ── App bar ──────────────────────────────────────────────
              SliverToBoxAdapter(
                child: _HomeAppBar(
                  dealerName: session?.name ?? 'منشی',
                  onSearch: () => context.go(AppRoutes.search),
                  onNotifications: () => context.go(AppRoutes.notifications),
                ),
              ),

              // ── Content ──────────────────────────────────────────────
              dashAsync.when(
                loading: () => const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.base),
                    child: ListSkeleton(itemCount: 4, itemHeight: 100),
                  ),
                ),
                error: (e, _) => SliverToBoxAdapter(
                  child: ErrorState.generic(
                    onRetry: () =>
                        ref.read(dashboardProvider.notifier).refresh(),
                  ),
                ),
                data: (summary) => _HomeContent(
                  summary: summary,
                  countUpCtrl: _countUpCtrl,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── App bar ────────────────────────────────────────────────────────────────

class _HomeAppBar extends ConsumerWidget {
  final String dealerName;
  final VoidCallback onSearch;
  final VoidCallback onNotifications;

  const _HomeAppBar({
    required this.dealerName,
    required this.onSearch,
    required this.onNotifications,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.base,
        0,
      ),
      child: Row(
        children: [
          // Title
          Expanded(
            child: Text(
              'آج کا حساب',
              style: AppTypography.urH1.copyWith(color: AppColors.ink900),
              textDirection: TextDirection.rtl,
            ),
          ),

          // Search
          IconButton(
            onPressed: onSearch,
            icon: const Icon(Icons.search_rounded),
            iconSize: 26,
            tooltip: 'تلاش',
          ),

          // Notifications
          IconButton(
            onPressed: onNotifications,
            icon: const Icon(Icons.notifications_rounded),
            iconSize: 26,
            tooltip: 'اطلاعات',
          ),
        ],
      ),
    );
  }
}

// ── Main content ───────────────────────────────────────────────────────────

class _HomeContent extends ConsumerWidget {
  final DashboardSummary? summary;
  final AnimationController countUpCtrl;

  const _HomeContent({required this.summary, required this.countUpCtrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SliverList(
      delegate: SliverChildListDelegate([
        // ── Commission hero (the money screen owners open daily) ────
        _CommissionHero(
          summary: summary,
          countUpCtrl: countUpCtrl,
        ),

        const SizedBox(height: AppSpacing.lg),

        // ── 3 giant action buttons ────────────────────────────────
        _HomeActionButtons(),

        const SizedBox(height: AppSpacing.xl),

        // ── Stage strip ───────────────────────────────────────────
        if (summary != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
            child: _StageSummaryStrip(summary: summary!),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],

        // ── Expiring tokens (pulsing red) ─────────────────────────
        if (summary != null && summary!.expiringTokens.isNotEmpty) ...[
          _ExpiringTokensSection(tokens: summary!.expiringTokens),
          const SizedBox(height: AppSpacing.base),
        ],

        // ── Follow-ups due today ──────────────────────────────────
        if (summary != null && summary!.followupsDueToday.isNotEmpty) ...[
          _FollowupsDueTodaySection(followups: summary!.followupsDueToday),
          const SizedBox(height: AppSpacing.base),
        ],

        // Bottom padding
        const SizedBox(height: AppSpacing.xxl),
      ]),
    );
  }
}

// ── Commission hero ────────────────────────────────────────────────────────

class _CommissionHero extends ConsumerWidget {
  final DashboardSummary? summary;
  final AnimationController countUpCtrl;

  const _CommissionHero({required this.summary, required this.countUpCtrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expectedRs = summary?.expectedCommissionRs ?? 0;
    final receivedRs = summary?.commissionReceivedRs ?? 0;
    final tts = ref.read(ttsServiceProvider);

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.base,
        0,
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.brand900, AppColors.brand700],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: AppSpacing.cardRadius,
        boxShadow: [
          BoxShadow(
            color: AppColors.brand900.withAlpha(80),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label
          Text(
            'اس مہینے کا توقع کمیشن',
            style: AppTypography.urBody.copyWith(color: AppColors.brand100),
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: AppSpacing.sm),

          // Big commission figure with count-up animation
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: AnimatedBuilder(
                  animation: countUpCtrl,
                  builder: (_, __) {
                    final displayAmount =
                        (expectedRs * countUpCtrl.value).round();
                    return Text(
                      formatMoney(displayAmount),
                      style: AppTypography.moneyHero.copyWith(
                        color: AppColors.gold500,
                        fontSize: 36,
                      ),
                      textDirection: TextDirection.ltr,
                    );
                  },
                ),
              ),

              // 🔊 Speak button
              GestureDetector(
                onTap: () async {
                  HapticFeedback.lightImpact();
                  await tts.speak(
                    'اس مہینے آپ کا ${speakAmount(expectedRs)} متوقع ہے',
                  );
                },
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.gold500.withAlpha(30),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.gold500.withAlpha(80)),
                  ),
                  child: const Icon(
                    Icons.volume_up_rounded,
                    color: AppColors.gold500,
                    size: 26,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: AppSpacing.md),

          // Received this month
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'موصول',
                style: AppTypography.urBody.copyWith(color: AppColors.brand100),
              ),
              Text(
                formatMoney(receivedRs),
                style: AppTypography.moneyMedium.copyWith(
                  color: AppColors.success,
                ),
                textDirection: TextDirection.ltr,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 3 giant action buttons ─────────────────────────────────────────────────

class _HomeActionButtons extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          BigActionButton(
            icon: Icons.arrow_downward_rounded,
            labelUr: 'پیسہ آیا',
            color: AppColors.moneyIn,
            onTap: () => context.push(AppRoutes.paisaAya),
          ),
          BigActionButton(
            icon: Icons.arrow_upward_rounded,
            labelUr: 'پیسہ گیا',
            color: AppColors.moneyOut,
            onTap: () => context.push(AppRoutes.paisaGaya),
          ),
          BigActionButton(
            icon: Icons.add_rounded,
            labelUr: 'نیا ڈیل',
            color: AppColors.brand600,
            onTap: () => context.push(AppRoutes.nayaDeal),
          ),
        ],
      ),
    );
  }
}

// ── Stage summary strip ────────────────────────────────────────────────────

class _StageSummaryStrip extends StatelessWidget {
  final DashboardSummary summary;
  const _StageSummaryStrip({required this.summary});

  @override
  Widget build(BuildContext context) {
    final stages = [
      (stage: DealStage.inquiry,  count: summary.stageInquiry),
      (stage: DealStage.token,    count: summary.stageToken),
      (stage: DealStage.bayana,   count: summary.stageBayana),
      (stage: DealStage.registry, count: summary.stageRegistry),
    ];

    return Row(
      children: stages.map((s) {
        if (s.count == 0) return const SizedBox.shrink();
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _StageCountChip(stage: s.stage, count: s.count),
          ),
        );
      }).toList(),
    );
  }
}

class _StageCountChip extends StatelessWidget {
  final DealStage stage;
  final int count;
  const _StageCountChip({required this.stage, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: stage.color.withAlpha(20),
        borderRadius: AppSpacing.cardRadius,
        border: Border.all(color: stage.color.withAlpha(60)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(stage.icon, size: 14, color: stage.color),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: AppTypography.moneySmall.copyWith(color: stage.color),
          ),
        ],
      ),
    );
  }
}

// ── Expiring tokens ────────────────────────────────────────────────────────

class _ExpiringTokensSection extends StatelessWidget {
  final List<ExpiringToken> tokens;
  const _ExpiringTokensSection({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          icon: Icons.warning_amber_rounded,
          iconColor: AppColors.danger,
          label: 'ٹوکن ختم ہونے والے',
          count: tokens.length,
        ),
        ...tokens.map((t) => _ExpiringTokenCard(token: t)),
      ],
    );
  }
}

class _ExpiringTokenCard extends StatefulWidget {
  final ExpiringToken token;
  const _ExpiringTokenCard({required this.token});

  @override
  State<_ExpiringTokenCard> createState() => _ExpiringTokenCardState();
}

class _ExpiringTokenCardState extends State<_ExpiringTokenCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.token.daysUntilExpiry;
    final isUrgent = widget.token.isUrgent;
    final commRs = widget.token.expectedCommRs ?? 0;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) {
        return Container(
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.base, 0, AppSpacing.base, AppSpacing.sm,
          ),
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: AppColors.danger.withAlpha(
              isUrgent ? (15 + (15 * _pulse.value)).round() : 10,
            ),
            borderRadius: AppSpacing.cardRadius,
            border: Border.all(
              color: AppColors.danger.withAlpha(
                isUrgent ? (80 + (80 * _pulse.value)).round() : 60,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.access_time_rounded,
                color: AppColors.danger,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      days == 0
                          ? 'آج ختم ہو رہا ہے'
                          : '$days دن باقی',
                      style: AppTypography.urBodyBold.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                    if (commRs > 0)
                      Text(
                        formatMoney(commRs),
                        style: AppTypography.moneySmall.copyWith(
                          color: AppColors.ink500,
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => context.push(
                  '${AppRoutes.deals}/${widget.token.dealId}',
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: AppSpacing.pillRadius,
                  ),
                  child: Text(
                    'دیکھیں',
                    style: AppTypography.urCaption.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Follow-ups due today ───────────────────────────────────────────────────

class _FollowupsDueTodaySection extends StatelessWidget {
  final List<DueTodayFollowup> followups;
  const _FollowupsDueTodaySection({required this.followups});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          icon: Icons.phone_rounded,
          iconColor: AppColors.brand600,
          label: 'آج کے فالو اپ',
          count: followups.length,
        ),
        ...followups.take(3).map((f) => _FollowupCard(followup: f)),
        if (followups.length > 3)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.base, 0, AppSpacing.base, 0,
            ),
            child: TextButton(
              onPressed: () => context.go(AppRoutes.followups),
              child: Text(
                '${followups.length - 3} مزید دیکھیں',
                style: AppTypography.urBody.copyWith(color: AppColors.brand600),
              ),
            ),
          ),
      ],
    );
  }
}

class _FollowupCard extends StatelessWidget {
  final DueTodayFollowup followup;
  const _FollowupCard({required this.followup});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.base, 0, AppSpacing.base, AppSpacing.sm,
      ),
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: AppSpacing.cardRadius,
        border: Border.all(color: AppColors.ink100),
      ),
      child: Row(
        children: [
          // Avatar placeholder
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.brand100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              followup.kind == 'call'
                  ? Icons.phone_rounded
                  : Icons.chat_rounded,
              color: AppColors.brand600,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.base),
          Expanded(
            child: Text(
              followup.noteText ?? 'فالو اپ',
              style: AppTypography.urBodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Call button
          GestureDetector(
            onTap: () => context.go(AppRoutes.followups),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.phone_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final int count;

  const _SectionHeader({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        0,
        AppSpacing.base,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: AppTypography.urBodyBold.copyWith(color: AppColors.ink700),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: iconColor.withAlpha(20),
              borderRadius: AppSpacing.pillRadius,
            ),
            child: Text(
              '$count',
              style: AppTypography.caption.copyWith(
                color: iconColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
