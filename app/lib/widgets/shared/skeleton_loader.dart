import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// Skeleton loaders — shimmer placeholders matching card shapes.
/// No spinners on lists. No text during loading.
class CardSkeleton extends StatelessWidget {
  final double height;
  final double? width;
  final EdgeInsetsGeometry? margin;

  const CardSkeleton({
    this.height = 80,
    this.width,
    this.margin,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.ink100,
      highlightColor: AppColors.paper,
      child: Container(
        height: height,
        width: width,
        margin: margin ?? const EdgeInsets.only(bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppSpacing.cardRadius,
        ),
      ),
    );
  }
}

class ListSkeleton extends StatelessWidget {
  final int itemCount;
  final double itemHeight;

  const ListSkeleton({
    this.itemCount = 5,
    this.itemHeight = 80,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        itemCount,
        (i) => CardSkeleton(
          height: itemHeight,
          margin: EdgeInsets.only(
            bottom: AppSpacing.sm,
            top: i == 0 ? AppSpacing.base : 0,
          ),
        ),
      ),
    );
  }
}

class AvatarSkeleton extends StatelessWidget {
  final double size;
  const AvatarSkeleton({this.size = 48, super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.ink100,
      highlightColor: AppColors.paper,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Skeleton → Content crossfade (200ms, no flash).
class SkeletonFade extends StatelessWidget {
  final bool isLoading;
  final Widget skeleton;
  final Widget child;

  const SkeletonFade({
    required this.isLoading,
    required this.skeleton,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      firstChild: skeleton,
      secondChild: child,
      crossFadeState:
          isLoading ? CrossFadeState.showFirst : CrossFadeState.showSecond,
      duration: const Duration(milliseconds: 200),
    );
  }
}
