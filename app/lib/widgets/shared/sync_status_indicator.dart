import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/offline/sync_state.dart';
import '../../core/services/tts_service.dart';

/// Sync status indicator — shown in app shell corner.
///
/// States:
/// 🟡 Pulsing amber = syncing ("save ho raha hai")
/// ✅ Green check (3s then fades) = all synced ("ho gaya")
/// 🔴 Red dot = failed operations
///
/// Tap → opens sync status detail sheet.
class SyncStatusIndicator extends ConsumerWidget {
  const SyncStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncStateProvider);

    if (syncState.status == SyncStatus.idle) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () => _showDetail(context, ref, syncState),
      child: _SyncDot(status: syncState.status),
    );
  }

  void _showDetail(BuildContext context, WidgetRef ref, SyncState state) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _SyncDetailSheet(syncState: state),
    );
  }
}

class _SyncDot extends StatefulWidget {
  final SyncStatus status;
  const _SyncDot({required this.status});

  @override
  State<_SyncDot> createState() => _SyncDotState();
}

class _SyncDotState extends State<_SyncDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _updateAnimation();
  }

  @override
  void didUpdateWidget(_SyncDot old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status) _updateAnimation();
  }

  void _updateAnimation() {
    if (widget.status == SyncStatus.syncing) {
      _ctrl.repeat(reverse: true);
      _visible = true;
    } else if (widget.status == SyncStatus.synced) {
      _ctrl.stop();
      _ctrl.value = 1;
      // Auto-hide after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _visible = false);
      });
    } else {
      _ctrl.stop();
      _ctrl.value = 1;
      _visible = true;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _color => switch (widget.status) {
    SyncStatus.syncing => AppColors.warn,
    SyncStatus.synced  => AppColors.success,
    SyncStatus.failed  => AppColors.danger,
    SyncStatus.idle    => Colors.transparent,
  };

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            shape: BoxShape.circle,
            boxShadow: AppElevation.low,
          ),
          child: Center(
            child: Container(
              width: 12, height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _color.withAlpha(
                  widget.status == SyncStatus.syncing
                      ? (150 + (100 * _ctrl.value)).round()
                      : 255,
                ),
                boxShadow: widget.status == SyncStatus.syncing
                    ? [BoxShadow(
                        color: _color.withAlpha((60 * _ctrl.value).round()),
                        blurRadius: 6 * _ctrl.value,
                      )]
                    : null,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Sync detail bottom sheet.
class _SyncDetailSheet extends ConsumerWidget {
  final SyncState syncState;
  const _SyncDetailSheet({required this.syncState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Icon(
                _statusIcon,
                color: _statusColor,
                size: 24,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(_statusText, style: AppTypography.urH2),
              const Spacer(),
              if (syncState.lastSyncedAt != null)
                Text(
                  _formatTime(syncState.lastSyncedAt!),
                  style: AppTypography.caption,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.base),

          // Conflicts (financial — need attention)
          if (syncState.conflicts.isNotEmpty) ...[
            Text(
              'تنازعات (${syncState.conflicts.length})',
              style: AppTypography.urBodyBold.copyWith(color: AppColors.danger),
            ),
            const SizedBox(height: AppSpacing.sm),
            ...syncState.conflicts.map((c) => _IssueRow(
                  icon: Icons.warning_amber_rounded,
                  color: AppColors.danger,
                  message: c.message,
                )),
            const SizedBox(height: AppSpacing.base),
          ],

          // Failures (network/retry)
          if (syncState.failures.isNotEmpty) ...[
            Text(
              'ناکام (${syncState.failures.length})',
              style: AppTypography.urBodyBold.copyWith(color: AppColors.warn),
            ),
            const SizedBox(height: AppSpacing.sm),
            ...syncState.failures.take(3).map((f) => _IssueRow(
                  icon: Icons.sync_problem_rounded,
                  color: AppColors.warn,
                  message: f.error,
                )),
            const SizedBox(height: AppSpacing.base),
          ],

          // Actions
          if (syncState.hasIssues)
            OutlinedButton.icon(
              onPressed: () {
                ref.read(syncStateProvider.notifier).clearResolved();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.refresh_rounded),
              label: Text('دوبارہ کوشش', style: AppTypography.urBodyMedium),
            ),

          // Voice status
          TextButton.icon(
            onPressed: () async {
              await ref.read(ttsServiceProvider).speak(_statusText);
            },
            icon: const Icon(Icons.volume_up_rounded, color: AppColors.brand600),
            label: Text(
              'سنیں',
              style: AppTypography.urBody.copyWith(color: AppColors.brand600),
            ),
          ),
        ],
      ),
    );
  }

  IconData get _statusIcon => switch (syncState.status) {
    SyncStatus.syncing => Icons.sync_rounded,
    SyncStatus.synced  => Icons.check_circle_rounded,
    SyncStatus.failed  => Icons.error_outline_rounded,
    SyncStatus.idle    => Icons.cloud_done_rounded,
  };

  Color get _statusColor => switch (syncState.status) {
    SyncStatus.syncing => AppColors.warn,
    SyncStatus.synced  => AppColors.success,
    SyncStatus.failed  => AppColors.danger,
    SyncStatus.idle    => AppColors.ink300,
  };

  String get _statusText => switch (syncState.status) {
    SyncStatus.syncing => 'سیو ہو رہا ہے...',
    SyncStatus.synced  => 'ہو گیا',
    SyncStatus.failed  => 'سیو نہیں ہوا',
    SyncStatus.idle    => 'تیار',
  };

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _IssueRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;
  const _IssueRow({required this.icon, required this.color, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTypography.caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
