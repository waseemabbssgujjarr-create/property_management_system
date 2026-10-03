import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/services/tts_service.dart';
import '../../../widgets/shared/skeleton_loader.dart';
import '../../auth/providers/session_provider.dart';
import '../../money/repositories/money_repository.dart';

/// Staff screen — per-staff earned vs paid this month.
/// The "moat screen" — nobody else has this simple owner view.
/// Owner hears it as a voice summary.
class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    final staffAsync = ref.watch(_staffSummaryProvider(session?.dealerId ?? ''));

    return Scaffold(
      appBar: AppBar(
        title: Text('ٹیم', style: AppTypography.urH2),
        actions: [
          // Voice summary for owner — reads all staff stats aloud
          IconButton(
            icon: const Icon(Icons.volume_up_rounded, color: AppColors.gold500),
            onPressed: () async {
              final list = staffAsync.valueOrNull ?? [];
              await _speakSummary(ref, list);
            },
            tooltip: 'سنیں',
          ),
        ],
      ),
      body: staffAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.base),
          child: ListSkeleton(itemCount: 4, itemHeight: 100),
        ),
        error: (e, _) => Center(
          child: Text(e.toString(), style: AppTypography.urBody),
        ),
        data: (staffList) => staffList.isEmpty
            ? const Center(
                child: Text('کوئی اسٹاف نہیں',
                    style: TextStyle(fontFamily: 'NotoNaskhArabic')),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.base),
                itemCount: staffList.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (_, i) => _StaffCard(
                  summary: staffList[i],
                  // Pass ref through constructor to avoid broken ancestor lookup
                  onSpeak: (text) async {
                    await ref.read(ttsServiceProvider).speak(text);
                  },
                ),
              ),
      ),
    );
  }

  Future<void> _speakSummary(WidgetRef ref, List<StaffCommSummary> list) async {
    if (list.isEmpty) {
      await ref.read(ttsServiceProvider).speak('کوئی اسٹاف نہیں');
      return;
    }
    final parts = list.map((s) =>
      '${s.name} — ${speakAmount(s.earnedRs)} بنا، ${speakAmount(s.paidRs)} ملا',
    ).join('۔ ');
    await ref.read(ttsServiceProvider).speak('اس مہینے: $parts');
  }
}

class _StaffCard extends StatelessWidget {
  final StaffCommSummary summary;
  final Future<void> Function(String text) onSpeak;

  const _StaffCard({required this.summary, required this.onSpeak});

  @override
  Widget build(BuildContext context) {
    final pending = summary.earnedRs - summary.paidRs;
    final progressPct = summary.earnedRs > 0
        ? (summary.paidRs / summary.earnedRs).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: AppSpacing.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.brand100,
                child: Text(
                  summary.name.isNotEmpty ? summary.name[0] : '?',
                  style: AppTypography.urBodyBold
                      .copyWith(color: AppColors.brand600),
                ),
              ),
              const SizedBox(width: AppSpacing.base),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.name,
                      style: AppTypography.urBodyMedium,
                      textDirection: TextDirection.rtl,
                    ),
                    Text(summary.roleUr, style: AppTypography.caption),
                  ],
                ),
              ),
              // Voice summary button — uses callback, no ancestor lookup
              GestureDetector(
                onTap: () async {
                  final spoken =
                    '${summary.name} کو ${speakAmount(summary.earnedRs)} بنتا ہے، '
                    '${speakAmount(summary.paidRs)} مل گیا';
                  await onSpeak(spoken);
                },
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.brand100,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.volume_up_rounded,
                    size: 18,
                    color: AppColors.brand600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.base),

          // Earned / Paid / Pending row + progress ring
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MoneyRow('بنا', summary.earnedRs, AppColors.success),
                    const SizedBox(height: 4),
                    _MoneyRow('ملا', summary.paidRs, AppColors.brand600),
                    if (pending > 0) ...[
                      const SizedBox(height: 4),
                      _MoneyRow('باقی', pending, AppColors.warn),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.base),
              SizedBox(
                width: 56, height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progressPct,
                      strokeWidth: 5,
                      backgroundColor: AppColors.ink100,
                      color: AppColors.success,
                    ),
                    Text(
                      '${(progressPct * 100).round()}%',
                      style: AppTypography.caption
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  final String label;
  final int rupees;
  final Color color;
  const _MoneyRow(this.label, this.rupees, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.urCaption),
        Text(
          formatMoney(rupees),
          style: AppTypography.moneySmall.copyWith(color: color),
          textDirection: TextDirection.ltr,
        ),
      ],
    );
  }
}

// ── Staff commission summary model ────────────────────────────────────────

class StaffCommSummary {
  final String userId;
  final String name;
  final String role;
  final int earnedRs;
  final int paidRs;

  const StaffCommSummary({
    required this.userId,
    required this.name,
    required this.role,
    required this.earnedRs,
    required this.paidRs,
  });

  int get pendingRs => earnedRs - paidRs;

  String get roleUr => switch (role) {
    'owner'   => 'مالک',
    'manager' => 'مینیجر',
    'agent'   => 'ایجنٹ',
    'munshi'  => 'منشی',
    _         => role,
  };
}

// ── Provider ──────────────────────────────────────────────────────────────

final _staffSummaryProvider =
    FutureProvider.family<List<StaffCommSummary>, String>((ref, dealerId) async {
  if (dealerId.isEmpty) return [];
  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month, 1);
  final monthEnd = DateTime(now.year, now.month + 1, 1);

  // Use MoneyRepository RPC — no direct Supabase call from provider
  final data = await ref.read(moneyRepositoryProvider).getStaffCommissionSummary(
    dealerId: dealerId,
    monthStart: monthStart,
    monthEnd: monthEnd,
  );

  return data.map((m) => StaffCommSummary(
    userId: m['user_id'] as String,
    name: m['user_name'] as String? ?? '',
    role: m['user_role'] as String? ?? 'agent',
    earnedRs: m['earned_rs'] as int? ?? 0,
    paidRs: m['paid_rs_month'] as int? ?? 0,
  )).toList();
});
