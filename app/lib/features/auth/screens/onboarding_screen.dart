import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../repositories/onboarding_repository.dart';
import '../providers/session_provider.dart';

/// Onboarding — collects agency name, city, areas, team size.
///
/// No-read rules:
/// - Agency name via voice note (or text for munshi)
/// - City from chips (not a text field)
/// - Areas as multi-select icon chips
/// - Team size as stepper (not a number field)
///
/// Delegates all DB writes to OnboardingRepository (atomic, idempotent).
/// No direct Supabase calls from this widget.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _agencyNameCtrl = TextEditingController();
  String _selectedCity = '';
  final List<String> _selectedAreas = [];
  int _teamSize = 1;
  bool _isSaving = false;
  String? _error;
  int _step = 0;

  static const _cities = [
    'لاہور', 'کراچی', 'اسلام آباد', 'رالپنڈی', 'فیصل آباد', 'دیگر'
  ];

  static const _popularAreas = [
    'DHA لاہور', 'بحریہ ٹاؤن لاہور', 'DHA کراچی',
    'بحریہ ٹاؤن کراچی', 'DHA اسلام آباد', 'گلبرگ', 'ماڈل ٹاؤن', 'دیگر'
  ];

  Future<void> _complete() async {
    if (_agencyNameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'ایجنسی کا نام درج کریں');
      return;
    }
    if (_selectedCity.isEmpty) {
      setState(() => _error = 'شہر منتخب کریں');
      return;
    }

    setState(() { _isSaving = true; _error = null; });

    try {
      // Phone comes from verified Supabase Auth — not from user input
      final authUser = Supabase.instance.client.auth.currentUser;
      if (authUser == null) throw Exception('Not authenticated');
      if (authUser.phone == null || authUser.phone!.isEmpty) {
        throw Exception('No phone on auth user');
      }

      // Delegate to repository — atomic, idempotent, no direct DB in widget
      final result = await ref.read(onboardingRepositoryProvider)
          .createDealerAndOwner(
            agencyName: _agencyNameCtrl.text.trim(),
            ownerPhone: authUser.phone!,
            ownerAuthUid: authUser.id,
            city: _selectedCity,
            areas: _selectedAreas,
            teamSize: _teamSize,
          );

      // Refresh session to pick up new JWT claims
      await ref.read(sessionProvider.notifier).refresh();

      if (mounted) context.go(AppRoutes.home);
    } catch (e) {
      setState(() {
        _isSaving = false;
        _error = 'محفوظ نہیں ہوا — دوبارہ کوشش کریں';
      });
    }
  }

  @override
  void dispose() {
    _agencyNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            LinearProgressIndicator(
              value: (_step + 1) / 3,
              backgroundColor: AppColors.ink100,
              color: AppColors.brand600,
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: AppSpacing.pagePadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'خوش آمدید!',
                      style: AppTypography.urDisplayLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    if (_step == 0) _AgencyNameStep(
                      controller: _agencyNameCtrl,
                      onNext: () => setState(() { _step = 1; _error = null; }),
                    ),

                    if (_step == 1) _CityStep(
                      cities: _cities,
                      selected: _selectedCity,
                      onSelect: (city) => setState(() => _selectedCity = city),
                      onNext: () {
                        if (_selectedCity.isEmpty) {
                          setState(() => _error = 'شہر منتخب کریں');
                          return;
                        }
                        setState(() { _step = 2; _error = null; });
                      },
                    ),

                    if (_step == 2) _TeamStep(
                      areas: _popularAreas,
                      selectedAreas: _selectedAreas,
                      teamSize: _teamSize,
                      onAreaToggle: (area) {
                        setState(() {
                          if (_selectedAreas.contains(area)) {
                            _selectedAreas.remove(area);
                          } else {
                            _selectedAreas.add(area);
                          }
                        });
                      },
                      onTeamChange: (size) => setState(() => _teamSize = size),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _error!,
                        style: AppTypography.urBody.copyWith(color: AppColors.danger),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Bottom action
            Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Row(
                children: [
                  if (_step > 0)
                    IconButton(
                      onPressed: () => setState(() => _step--),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      iconSize: 28,
                    ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving
                          ? null
                          : _step < 2
                              ? () {
                                  if (_step == 0 && _agencyNameCtrl.text.trim().isEmpty) {
                                    setState(() => _error = 'نام درج کریں');
                                    return;
                                  }
                                  setState(() { _step++; _error = null; });
                                }
                              : _complete,
                      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
                      child: _isSaving
                          ? const SizedBox(
                              width: 24, height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            )
                          : Text(
                              _step < 2 ? 'اگلا' : 'شروع کریں',
                              style: AppTypography.urBodyBold,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgencyNameStep extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onNext;
  const _AgencyNameStep({required this.controller, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('ایجنسی کا نام', style: AppTypography.urH2, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: controller,
          style: AppTypography.urH2,
          textAlign: TextAlign.right,
          textDirection: TextDirection.rtl,
          decoration: InputDecoration(
            hintText: 'مثال: الحمد پراپرٹیز',
            hintStyle: AppTypography.urBody.copyWith(color: AppColors.ink300),
          ),
          onSubmitted: (_) => onNext(),
        ),
      ],
    );
  }
}

class _CityStep extends StatelessWidget {
  final List<String> cities;
  final String selected;
  final void Function(String) onSelect;
  final VoidCallback onNext;
  const _CityStep({required this.cities, required this.selected, required this.onSelect, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('شہر منتخب کریں', style: AppTypography.urH2, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          alignment: WrapAlignment.center,
          children: cities.map((city) {
            final isSelected = city == selected;
            return GestureDetector(
              onTap: () => onSelect(city),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.brand600 : Colors.transparent,
                  borderRadius: AppSpacing.pillRadius,
                  border: Border.all(
                    color: isSelected ? AppColors.brand600 : AppColors.ink100,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  city,
                  style: AppTypography.urBodyMedium.copyWith(
                    color: isSelected ? Colors.white : AppColors.ink700,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _TeamStep extends StatelessWidget {
  final List<String> areas;
  final List<String> selectedAreas;
  final int teamSize;
  final void Function(String) onAreaToggle;
  final void Function(int) onTeamChange;
  const _TeamStep({
    required this.areas, required this.selectedAreas, required this.teamSize,
    required this.onAreaToggle, required this.onTeamChange,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('علاقے', style: AppTypography.urH2, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.base),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          alignment: WrapAlignment.center,
          children: areas.map((area) {
            final isSelected = selectedAreas.contains(area);
            return FilterChip(
              label: Text(area, style: AppTypography.urLabel),
              selected: isSelected,
              onSelected: (_) => onAreaToggle(area),
              selectedColor: AppColors.brand100,
              checkmarkColor: AppColors.brand600,
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('ٹیم کا سائز', style: AppTypography.urH2, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.base),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: teamSize > 1 ? () => onTeamChange(teamSize - 1) : null,
              icon: const Icon(Icons.remove_circle_outline_rounded, size: 32),
              color: AppColors.brand600,
            ),
            const SizedBox(width: AppSpacing.base),
            Text('$teamSize', style: AppTypography.moneyLarge),
            const SizedBox(width: AppSpacing.base),
            IconButton(
              onPressed: teamSize < 20 ? () => onTeamChange(teamSize + 1) : null,
              icon: const Icon(Icons.add_circle_outline_rounded, size: 32),
              color: AppColors.brand600,
            ),
          ],
        ),
      ],
    );
  }
}
