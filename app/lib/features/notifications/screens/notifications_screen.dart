import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../widgets/shared/empty_state.dart';
import '../../../widgets/shared/skeleton_loader.dart';
import '../../auth/providers/session_provider.dart';
import '../repositories/notifications_repository.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    final dealerId = session?.dealerId ?? '';
    final notifAsync = ref.watch(_notificationsProvider(dealerId));

    return Scaffold(
      appBar: AppBar(
        title: Text('اطلاعات', style: AppTypography.urH2),
        actions: [
          TextButton(
            onPressed: dealerId.isEmpty
                ? null
                : () async {
                    await ref
                        .read(notificationsRepositoryProvider)
                        .markAllRead(dealerId);
                    ref.invalidate(_notificationsProvider(dealerId));
                  },
            child: Text('سب پڑھیں',
                style: AppTypography.urBody.copyWith(color: AppColors.brand600)),
          ),
        ],
      ),
      body: notifAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.base),
          child: ListSkeleton(itemCount: 5, itemHeight: 70),
        ),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (notifications) => notifications.isEmpty
            ? const EmptyState(
                icon: Icons.notifications_none_rounded,
                messageUr: 'کوئی اطلاع نہیں',
              )
            : ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.base),
                itemCount: notifications.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => _NotifTile(n: notifications[i]),
              ),
      ),
    );
  }
}

final _notificationsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, dealerId) async {
    if (dealerId.isEmpty) return [];
    return ref
        .read(notificationsRepositoryProvider)
        .getNotifications(dealerId: dealerId);
  },
);

class _NotifTile extends StatelessWidget {
  final Map<String, dynamic> n;
  const _NotifTile({required this.n});

  IconData get _icon => switch (n['kind'] as String? ?? '') {
    'token_expiring'   => Icons.timer_outlined,
    'bayana_due'       => Icons.description_outlined,
    'followup_due'     => Icons.phone_outlined,
    'payment_received' => Icons.payments_outlined,
    _                  => Icons.notifications_outlined,
  };

  Color get _color => switch (n['kind'] as String? ?? '') {
    'token_expiring' => AppColors.danger,
    'bayana_due'     => AppColors.stageBayana,
    'followup_due'   => AppColors.brand600,
    _                => AppColors.ink500,
  };

  bool get _isRead => n['read_at'] != null;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _isRead ? null : AppColors.brand50,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _color.withAlpha(20),
          child: Icon(_icon, color: _color, size: 20),
        ),
        title: Text(
          n['title_ur'] as String? ?? '',
          style: AppTypography.urBodyMedium.copyWith(
            fontWeight: _isRead ? FontWeight.w400 : FontWeight.w700,
          ),
          textDirection: TextDirection.rtl,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((n['body_ur'] as String? ?? '').isNotEmpty)
              Text(n['body_ur'] as String,
                  style: AppTypography.caption,
                  textDirection: TextDirection.rtl),
            Text(
              _formatTime(n['created_at'] as String? ?? ''),
              style: AppTypography.caption.copyWith(color: AppColors.ink300),
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  String _formatTime(String isoString) {
    if (isoString.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }
}
