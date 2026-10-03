import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../providers/session_provider.dart';
import '../repositories/auth_repository.dart';

/// Splash screen — checks auth state and routes correctly.
/// Authenticated users go to Home; unauthenticated users go to OTP.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    // Give Supabase Auth time to restore session from storage
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    final authUser = Supabase.instance.client.auth.currentUser;

    if (authUser != null) {
      // Try to load the full session (dealer + user record)
      try {
        final session = await ref.read(authRepositoryProvider).loadSession();
        if (!mounted) return;
        if (session != null) {
          context.go(AppRoutes.home);
        } else {
          // Authenticated with Supabase but no dealer profile — needs onboarding
          context.go(AppRoutes.onboarding);
        }
      } catch (_) {
        if (mounted) context.go('${AppRoutes.otp}?phone=');
      }
    } else {
      context.go('${AppRoutes.otp}?phone=');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.brand900,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.menu_book_rounded, size: 80, color: AppColors.gold500),
            const SizedBox(height: 24),
            Text(
              'منشی',
              style: AppTypography.urDisplayLarge.copyWith(
                color: Colors.white,
                fontSize: 48,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'آپ کا ڈیجیٹل منشی',
              style: AppTypography.urBody.copyWith(color: AppColors.brand100),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(
              color: AppColors.gold500,
              strokeWidth: 2,
            ),
          ],
        ),
      ),
    );
  }
}
