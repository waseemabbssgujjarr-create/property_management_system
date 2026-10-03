import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../widgets/shared/empty_state.dart';
import '../../../widgets/shared/error_state.dart';
import '../../../widgets/shared/skeleton_loader.dart';
import '../../../widgets/deal/stage_strip.dart';
import '../models/property_models.dart';
import '../providers/inventory_provider.dart';

/// Inventory screen — property photo grid with status color-corners.
/// Quick-add = photo first, then details.
/// Search = mic button (speak the name) + text.
class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventoryAsync = ref.watch(inventoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('پراپرٹی', style: AppTypography.urH2),
        actions: [
          IconButton(
            onPressed: () => context.go(AppRoutes.search),
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            onPressed: () => _showAddOptions(context),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: inventoryAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.base),
          child: ListSkeleton(itemCount: 6, itemHeight: 120),
        ),
        error: (e, _) => ErrorState.generic(
          onRetry: () => ref.read(inventoryProvider.notifier).refresh(),
        ),
        data: (properties) => properties.isEmpty
            ? EmptyState(
                icon: Icons.villa_rounded,
                messageUr: 'کوئی پراپرٹی نہیں',
                ctaLabelUr: 'پراپرٹی شامل کریں',
                onCtaTap: () => _showAddOptions(context),
                speakText: 'کوئی پراپرٹی نہیں — شامل کرنے کے لیے بٹن دبائیں',
              )
            : _PropertyGrid(
                properties: properties,
                onRefresh: () =>
                    ref.read(inventoryProvider.notifier).refresh(),
              ),
      ),
    );
  }

  void _showAddOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => const _AddPropertySheet(),
    );
  }
}

class _PropertyGrid extends StatelessWidget {
  final List<Property> properties;
  final Future<void> Function() onRefresh;

  const _PropertyGrid({required this.properties, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.brand600,
      child: GridView.builder(
        padding: const EdgeInsets.all(AppSpacing.base),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.85,
          crossAxisSpacing: AppSpacing.sm,
          mainAxisSpacing: AppSpacing.sm,
        ),
        itemCount: properties.length,
        itemBuilder: (context, i) => _PropertyCard(property: properties[i]),
      ),
    );
  }
}

class _PropertyCard extends StatelessWidget {
  final Property property;
  const _PropertyCard({required this.property});

  @override
  Widget build(BuildContext context) {
    final statusColor = propertyStatusColor(property.status.dbValue);
    final hasPhoto = property.photoUrls.isNotEmpty;

    return GestureDetector(
      onTap: () => context.push('${AppRoutes.inventory}/${property.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: AppSpacing.cardRadius,
          boxShadow: AppElevation.low,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Photo with status color corner
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppSpacing.radiusCard),
                    ),
                    child: hasPhoto
                        ? Image.network(
                            property.photoUrls.first,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorBuilder: (_, __, ___) => _KindPlaceholder(kind: property.kind),
                          )
                        : _KindPlaceholder(kind: property.kind),
                  ),
                  // Status corner badge
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: AppSpacing.pillRadius,
                      ),
                      child: Text(
                        property.status.labelUr,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'NotoNaskhArabic',
                        ),
                      ),
                    ),
                  ),
                  // Exclusive badge
                  if (property.exclusive)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.gold500,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.star_rounded, size: 12, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            // Details
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    property.society,
                    style: AppTypography.urBodyMedium.copyWith(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.rtl,
                  ),
                  if (property.sizeLabel != null || property.block != null)
                    Text(
                      [property.sizeLabel, property.block != null ? 'بلاک ${property.block}' : null]
                          .whereType<String>()
                          .join(' • '),
                      style: AppTypography.caption,
                      maxLines: 1,
                    ),
                  if (property.demandRs != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      formatMoney(property.demandRs!),
                      style: AppTypography.moneySmall.copyWith(
                        color: AppColors.brand600,
                      ),
                      textDirection: TextDirection.ltr,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindPlaceholder extends StatelessWidget {
  final PropertyKind kind;
  const _KindPlaceholder({required this.kind});

  IconData get _icon => switch (kind) {
    PropertyKind.plot       => Icons.crop_square_rounded,
    PropertyKind.file       => Icons.description_rounded,
    PropertyKind.house      => Icons.home_rounded,
    PropertyKind.shop       => Icons.store_rounded,
    PropertyKind.commercial => Icons.business_rounded,
    PropertyKind.apartment  => Icons.apartment_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.brand100,
      child: Center(
        child: Icon(_icon, size: 48, color: AppColors.brand600),
      ),
    );
  }
}

/// Bottom sheet for adding property (photo-first quick-add).
class _AddPropertySheet extends StatelessWidget {
  const _AddPropertySheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'پراپرٹی شامل کریں',
            style: AppTypography.urH2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          // Photo-first option (primary)
          ListTile(
            leading: Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: AppColors.brand100,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.camera_alt_rounded, color: AppColors.brand600),
            ),
            title: Text('فوٹو سے شامل کریں', style: AppTypography.urBodyMedium),
            subtitle: Text('پہلے فوٹو، پھر تفصیل', style: AppTypography.caption),
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'فوٹو سے شامل کرنا جلد دستیاب ہوگا',
                    style: AppTypography.urBody.copyWith(color: Colors.white),
                  ),
                  backgroundColor: AppColors.brand600,
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: AppColors.brand50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.edit_rounded, color: AppColors.ink500),
            ),
            title: Text('تفصیل سے شامل کریں', style: AppTypography.urBodyMedium),
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'پراپرٹی فارم جلد دستیاب ہوگا',
                    style: AppTypography.urBody.copyWith(color: Colors.white),
                  ),
                  backgroundColor: AppColors.brand600,
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.base),
        ],
      ),
    );
  }
}
