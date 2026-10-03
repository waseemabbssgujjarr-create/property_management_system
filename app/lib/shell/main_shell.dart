import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/router/app_router.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/state/app_mode.dart';
import '../core/offline/sync_provider.dart';
import '../widgets/primitives/speak_button.dart';
import '../widgets/shared/sync_status_indicator.dart';

/// Bottom navigation shell.
///
/// 5 large tabs with icons + Urdu labels.
/// Press-and-hold any nav icon → speaks its Urdu name (no-read rule).
/// RTL-aware.
/// Sync engine is initialized here (eager — starts as soon as shell mounts).
class MainShell extends ConsumerWidget {
  final Widget child;
  const MainShell({required this.child, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;

    // Eagerly initialize sync engine when shell mounts
    ref.watch(syncEngineProvider);

    return Scaffold(
      body: Stack(
        children: [
          child,
          // Sync status overlay (bottom-right corner, above nav bar)
          Positioned(
            bottom: kBottomNavigationBarHeight + 12,
            right: AppSpacing.base,
            child: const SyncStatusIndicator(),
          ),
        ],
      ),
      bottomNavigationBar: _MunshiBottomNav(currentLocation: location),
    );
  }
}

class _MunshiBottomNav extends StatelessWidget {
  final String currentLocation;
  const _MunshiBottomNav({required this.currentLocation});

  @override
  Widget build(BuildContext context) {
    final items = _navItems(context);
    final currentIndex = _indexForLocation(currentLocation);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isSelected = index == currentIndex;

              return _NavItem(
                icon: item.icon,
                label: item.label,
                speakLabel: item.speakLabel,
                isSelected: isSelected,
                onTap: () => context.go(item.route),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  int _indexForLocation(String loc) {
    if (loc.startsWith('/deals')) return 1;
    if (loc.startsWith('/inventory')) return 2;
    if (loc.startsWith('/parties')) return 3;
    if (loc.startsWith('/followups') ||
        loc.startsWith('/staff') ||
        loc.startsWith('/settings') ||
        loc.startsWith('/reports')) return 4;
    return 0; // home
  }

  List<_NavItemData> _navItems(BuildContext context) => [
    _NavItemData(
      icon: Icons.home_rounded,
      label: 'گھر',
      speakLabel: 'گھر — آج کا حساب',
      route: AppRoutes.home,
    ),
    _NavItemData(
      icon: Icons.handshake_rounded,
      label: 'ڈیلز',
      speakLabel: 'ڈیلز — تمام ڈیلز',
      route: AppRoutes.deals,
    ),
    _NavItemData(
      icon: Icons.villa_rounded,
      label: 'پراپرٹی',
      speakLabel: 'پراپرٹی — انوینٹری',
      route: AppRoutes.inventory,
    ),
    _NavItemData(
      icon: Icons.people_rounded,
      label: 'کلائنٹ',
      speakLabel: 'کلائنٹ — خریدار اور فروخت کنندگان',
      route: AppRoutes.parties,
    ),
    _NavItemData(
      icon: Icons.more_horiz_rounded,
      label: 'مزید',
      speakLabel: 'مزید اختیارات',
      route: AppRoutes.followups,
    ),
  ];
}

class _NavItemData {
  final IconData icon;
  final String label;
  final String speakLabel;
  final String route;
  const _NavItemData({
    required this.icon,
    required this.label,
    required this.speakLabel,
    required this.route,
  });
}

/// Single bottom nav item with press-and-hold to speak.
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String speakLabel;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.speakLabel,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface.withAlpha(100);

    return SpeakOnHold(
      text: speakLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: AppSpacing.touchTarget + 20,
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: isSelected ? 1.1 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: AppTypography.urCaption.copyWith(
                  color: color,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
