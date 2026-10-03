import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../widgets/shared/empty_state.dart';
import '../../../widgets/shared/error_state.dart';
import '../../../widgets/shared/skeleton_loader.dart';
import '../../auth/providers/session_provider.dart';
import '../models/followup_models.dart';
import '../repositories/followups_repository.dart';

/// Follow-ups screen — due-today as tappable cards.
/// Party photo + big "call karo" button + voice-note play.
/// Swipe right = done (green). Swipe left = snooze (amber).
class FollowupsScreen extends ConsumerWidget {
  const FollowupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    final followupsAsync = ref.watch(_followupsProvider(session?.dealerId ?? ''));

    return Scaffold(
      appBar: AppBar(
        title: Text('فالو اپ', style: AppTypography.urH2),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showAddSheet(context, ref, session?.dealerId ?? ''),
          ),
        ],
      ),
      body: followupsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.base),
          child: ListSkeleton(itemCount: 5, itemHeight: 80),
        ),
        error: (e, _) => ErrorState.generic(
          onRetry: () => ref.invalidate(
            _followupsProvider(session?.dealerId ?? ''),
          ),
        ),
        data: (followups) {
          if (followups.isEmpty) {
            return const EmptyState(
              icon: Icons.check_circle_outline_rounded,
              messageUr: 'آج کوئی فالو اپ نہیں',
              speakText: 'آج کوئی فالو اپ نہیں — شاباش',
            );
          }

          final overdue = followups.where((f) => f.isOverdue).toList();
          final dueToday = followups.where((f) => f.isDueToday).toList();
          final upcoming = followups
              .where((f) => !f.isOverdue && !f.isDueToday)
              .take(10)
              .toList();

          return RefreshIndicator(
            color: AppColors.brand600,
            onRefresh: () async =>
                ref.invalidate(_followupsProvider(session?.dealerId ?? '')),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.base),
              children: [
                if (overdue.isNotEmpty) ...[
                  _SectionHeader(
                    label: 'گزر گئے',
                    icon: Icons.warning_amber_rounded,
                    color: AppColors.danger,
                    count: overdue.length,
                  ),
                  ...overdue.map((f) => _FollowupCard(
                        followup: f,
                        onDone: () => _markDone(ref, f, session?.dealerId ?? ''),
                        onSnooze: () => _snooze(ref, f, session?.dealerId ?? ''),
                      )),
                  const SizedBox(height: AppSpacing.base),
                ],
                if (dueToday.isNotEmpty) ...[
                  _SectionHeader(
                    label: 'آج',
                    icon: Icons.today_rounded,
                    color: AppColors.brand600,
                    count: dueToday.length,
                  ),
                  ...dueToday.map((f) => _FollowupCard(
                        followup: f,
                        onDone: () => _markDone(ref, f, session?.dealerId ?? ''),
                        onSnooze: () => _snooze(ref, f, session?.dealerId ?? ''),
                      )),
                  const SizedBox(height: AppSpacing.base),
                ],
                if (upcoming.isNotEmpty) ...[
                  _SectionHeader(
                    label: 'آنے والے',
                    icon: Icons.schedule_rounded,
                    color: AppColors.ink500,
                    count: upcoming.length,
                  ),
                  ...upcoming.map((f) => _FollowupCard(
                        followup: f,
                        onDone: () => _markDone(ref, f, session?.dealerId ?? ''),
                        onSnooze: () => _snooze(ref, f, session?.dealerId ?? ''),
                      )),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _markDone(WidgetRef ref, Followup f, String dealerId) async {
    HapticFeedback.mediumImpact();
    await ref.read(followupsRepositoryProvider).markDone(f.id, dealerId);
    ref.invalidate(_followupsProvider(dealerId));
  }

  Future<void> _snooze(WidgetRef ref, Followup f, String dealerId) async {
    HapticFeedback.lightImpact();
    final snoozedUntil = DateTime.now().add(const Duration(hours: 2));
    await ref.read(followupsRepositoryProvider).snooze(f.id, dealerId, snoozedUntil);
    ref.invalidate(_followupsProvider(dealerId));
  }

  void _showAddSheet(BuildContext context, WidgetRef ref, String dealerId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddFollowupSheet(),
    );
  }
}

// Provider
final _followupsProvider =
    FutureProvider.family<List<Followup>, String>((ref, dealerId) async {
  if (dealerId.isEmpty) return [];
  return ref.read(followupsRepositoryProvider).getFollowups(
    dealerId: dealerId,
    pendingOnly: true,
  );
});

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final int count;

  const _SectionHeader({
    required this.label,
    required this.icon,
    required this.color,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(label,
              style: AppTypography.urBodyBold.copyWith(color: color)),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: 2),
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              borderRadius: AppSpacing.pillRadius,
            ),
            child: Text('$count',
                style: AppTypography.caption.copyWith(
                  color: color, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _FollowupCard extends StatelessWidget {
  final Followup followup;
  final VoidCallback onDone;
  final VoidCallback onSnooze;

  const _FollowupCard({
    required this.followup,
    required this.onDone,
    required this.onSnooze,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Slidable(
        key: ValueKey(followup.id),
        // Swipe right = done (green)
        startActionPane: ActionPane(
          motion: const DrawerMotion(),
          extentRatio: 0.25,
          children: [
            SlidableAction(
              onPressed: (_) => onDone(),
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              icon: Icons.check_rounded,
              label: 'ہو گیا',
              borderRadius: AppSpacing.cardRadius,
            ),
          ],
        ),
        // Swipe left = snooze (amber)
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          extentRatio: 0.25,
          children: [
            SlidableAction(
              onPressed: (_) => onSnooze(),
              backgroundColor: AppColors.warn,
              foregroundColor: Colors.white,
              icon: Icons.snooze_rounded,
              label: 'بعد میں',
              borderRadius: AppSpacing.cardRadius,
            ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(
            color: followup.isOverdue
                ? AppColors.danger.withAlpha(10)
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: AppSpacing.cardRadius,
            border: Border.all(
              color: followup.isOverdue
                  ? AppColors.danger.withAlpha(60)
                  : AppColors.ink100,
            ),
          ),
          child: Row(
            children: [
              // Avatar
              _Avatar(followup: followup),
              const SizedBox(width: AppSpacing.base),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      followup.partyName ?? 'نامعلوم',
                      style: AppTypography.urBodyMedium,
                      textDirection: TextDirection.rtl,
                    ),
                    if (followup.noteText != null)
                      Text(
                        followup.noteText!,
                        style: AppTypography.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.rtl,
                      ),
                    Text(
                      _formatDue(followup.dueAt),
                      style: AppTypography.caption.copyWith(
                        color: followup.isOverdue
                            ? AppColors.danger
                            : AppColors.ink500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Big call button — no reading needed
              GestureDetector(
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  final phone = followup.partyPhone;
                  if (phone != null && phone.isNotEmpty) {
                    final uri = Uri(scheme: 'tel', path: phone);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  }
                },
                child: Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.phone_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDue(DateTime due) {
    final now = DateTime.now();
    final diff = due.difference(now);
    if (diff.isNegative) {
      final hours = diff.abs().inHours;
      if (hours < 24) return '$hours گھنٹے پہلے';
      return '${diff.abs().inDays} دن پہلے';
    }
    if (diff.inHours < 24) return '${diff.inHours} گھنٹے بعد';
    return '${diff.inDays} دن بعد';
  }
}

class _Avatar extends StatelessWidget {
  final Followup followup;
  const _Avatar({required this.followup});

  @override
  Widget build(BuildContext context) {
    if (followup.partyPhotoUrl != null) {
      return CircleAvatar(
        radius: 24,
        backgroundImage: NetworkImage(followup.partyPhotoUrl!),
      );
    }
    final name = followup.partyName ?? '?';
    final initial = name.isNotEmpty ? name[0] : '?';
    return CircleAvatar(
      radius: 24,
      backgroundColor: AppColors.brand100,
      child: Text(
        initial,
        style: AppTypography.urBodyBold.copyWith(color: AppColors.brand600),
      ),
    );
  }
}

class _AddFollowupSheet extends ConsumerStatefulWidget {
  const _AddFollowupSheet();

  @override
  ConsumerState<_AddFollowupSheet> createState() => _AddFollowupSheetState();
}

class _AddFollowupSheetState extends ConsumerState<_AddFollowupSheet> {
  FollowupKind _kind = FollowupKind.call;
  final _noteCtrl = TextEditingController();
  DateTime _dueAt = DateTime.now().add(const Duration(hours: 2));
  bool _saving = false;

  @override
  void dispose() { _noteCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentSessionProvider);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
        left: AppSpacing.base, right: AppSpacing.base, top: AppSpacing.base,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('نیا فالو اپ', style: AppTypography.urH2, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.base),
          Row(
            children: FollowupKind.values.map((k) {
              final active = k == _kind;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _kind = k),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: active ? AppColors.brand600 : AppColors.brand50,
                      borderRadius: AppSpacing.buttonRadius,
                    ),
                    child: Text(k.labelUr,
                      style: AppTypography.urCaption.copyWith(
                        color: active ? Colors.white : AppColors.brand600,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.base),
          TextField(
            controller: _noteCtrl,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              labelText: 'نوٹ',
              labelStyle: AppTypography.urLabel,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton(
            onPressed: _saving ? null : () async {
              if (session == null) return;
              setState(() => _saving = true);
              try {
                await ref.read(followupsRepositoryProvider).createFollowup(
                  dealerId: session.dealerId,
                  kind: _kind,
                  dueAt: _dueAt,
                  noteText: _noteCtrl.text.trim().isNotEmpty ? _noteCtrl.text.trim() : null,
                  createdBy: session.userId,
                );
                if (mounted) Navigator.pop(context);
              } catch (_) {
                setState(() => _saving = false);
              }
            },
            child: Text('محفوظ کریں', style: AppTypography.urBodyBold),
          ),
          const SizedBox(height: AppSpacing.base),
        ],
      ),
    );
  }
}
