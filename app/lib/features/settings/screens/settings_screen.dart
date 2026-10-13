import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/state/app_mode.dart';
import '../../../core/state/locale_state.dart';
import '../../../core/state/voice_state.dart';
import '../../../core/offline/sync_provider.dart';
import '../../../core/services/permission_service.dart';
import '../../auth/providers/session_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appModeSyncProvider);
    final voiceEnabled = ref.watch(voiceEnabledProvider);
    final locale = ref.watch(localeSyncProvider);
    final session = ref.watch(currentSessionProvider);
    // Initialize sync engine eagerly when settings screen is visible
    ref.watch(syncEngineProvider);
    final perms = ref.watch(permissionServiceProvider);

    return Scaffold(
      appBar: AppBar(title: Text('ترتیبات', style: AppTypography.urH2)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.base),
        children: [
          // Mode toggle — Simple vs Detail
          _SettingsTile(
            icon: Icons.view_comfortable_rounded,
            label: mode == AppMode.simple ? 'سادہ موڈ' : 'تفصیل موڈ',
            subtitle: mode == AppMode.simple
                ? 'مالک کے لیے — آسان'
                : 'منشی کے لیے — تفصیل',
            trailing: Switch(
              value: mode == AppMode.detail,
              onChanged: (_) =>
                  ref.read(appModeProvider.notifier).toggleMode(),
              activeColor: AppColors.brand600,
            ),
          ),
          const Divider(height: 1),

          // Voice on/off
          _SettingsTile(
            icon: Icons.volume_up_rounded,
            label: voiceEnabled ? 'آواز آن' : 'آواز آف',
            subtitle: 'بٹن دبا کر سنیں',
            trailing: Switch(
              value: voiceEnabled,
              onChanged: (_) =>
                  ref.read(voiceStateProvider.notifier).toggle(),
              activeColor: AppColors.brand600,
            ),
          ),
          const Divider(height: 1),

          // Language toggle
          _SettingsTile(
            icon: Icons.language_rounded,
            label: locale.isUrdu ? 'اردو' : 'English',
            subtitle: locale.isUrdu ? 'زبان: اردو' : 'Language: English',
            trailing: TextButton(
              onPressed: () =>
                  ref.read(localeProvider.notifier).toggleLocale(),
              child: Text(
                locale.isUrdu ? 'EN' : 'اردو',
                style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.brand600),
              ),
            ),
          ),
          const Divider(height: 1),

          // Subscription
          _SettingsTile(
            icon: Icons.workspace_premium_rounded,
            label: 'سبسکرپشن',
            subtitle: session?.plan == 'pro' ? 'پرو پلان' : 'اسٹارٹر پلان',
            onTap: () => context.push(AppRoutes.subscription),
          ),
          const Divider(height: 1),

          // WhatsApp — owner/manager only
          if (perms.can(Permission.manageWhatsApp)) ...[
            _SettingsTile(
              icon: Icons.chat_rounded,
              label: 'واٹس ایپ',
              subtitle: 'کنیکشن ترتیب دیں',
              onTap: () => context.push(AppRoutes.whatsapp),
            ),
            const Divider(height: 1),
          ],

          // Data export — Phase 2/3 feature
          _SettingsTile(
            icon: Icons.download_rounded,
            label: 'ڈیٹا نکالیں',
            subtitle: 'CSV فارمیٹ میں — جلد آ رہا ہے',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'ڈیٹا برآمد جلد دستیاب ہوگا',
                    style: AppTypography.urBody.copyWith(color: Colors.white),
                  ),
                  backgroundColor: AppColors.brand600,
                ),
              );
            },
          ),
          const Divider(height: 1),

          // Help videos — Phase 2/3 feature
          _SettingsTile(
            icon: Icons.play_circle_outline_rounded,
            label: 'مدد',
            subtitle: 'ویڈیو ٹیوٹوریل — جلد آ رہا ہے',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'ویڈیو مدد جلد دستیاب ہوگی',
                    style: AppTypography.urBody.copyWith(color: Colors.white),
                  ),
                  backgroundColor: AppColors.brand600,
                ),
              );
            },
          ),
          const Divider(height: 1),

          const SizedBox(height: AppSpacing.lg),

          // Sign out
          OutlinedButton.icon(
            onPressed: () async {
              await ref.read(sessionProvider.notifier).signOut();
              if (context.mounted) context.go(AppRoutes.otp + '?phone=');
            },
            icon: const Icon(Icons.logout_rounded, color: AppColors.danger),
            label: Text(
              'لاگ آوٹ',
              style: AppTypography.urBodyMedium.copyWith(
                  color: AppColors.danger),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
            ),
          ),

          const SizedBox(height: AppSpacing.base),

          // Version info
          Center(
            child: Text(
              'Munshi v1.0.0',
              style: AppTypography.caption.copyWith(color: AppColors.ink300),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: AppColors.brand100,
          borderRadius: BorderRadius.circular(AppSpacing.radiusChip),
        ),
        child: Icon(icon, color: AppColors.brand600, size: 20),
      ),
      title: Text(label, style: AppTypography.urBodyMedium,
          textDirection: TextDirection.rtl),
      subtitle: subtitle != null
          ? Text(subtitle!, style: AppTypography.caption,
              textDirection: TextDirection.rtl)
          : null,
      trailing: trailing ??
          (onTap != null
              ? const Icon(Icons.arrow_back_ios_rounded, size: 14)
              : null),
    );
  }
}
