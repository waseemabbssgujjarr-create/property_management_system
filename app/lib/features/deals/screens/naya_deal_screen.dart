import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/services/tts_service.dart';
import '../../../widgets/deal/stage_strip.dart';
import '../../../widgets/shared/error_state.dart';
import '../../../widgets/shared/skeleton_loader.dart';
import '../../../widgets/primitives/number_pad.dart';
import '../../inventory/providers/inventory_provider.dart';
import '../../inventory/models/property_models.dart';
import '../../parties/repositories/parties_repository.dart';
import '../../parties/models/party_models.dart';
import '../../../widgets/primitives/method_chips.dart';
import '../../auth/providers/session_provider.dart';
import '../models/deal_models.dart';
import '../providers/deals_provider.dart';

/// Naya Deal wizard — 3 steps, under 90 seconds, zero typing required.
/// Step 1: Property (photo cards or quick-add)
/// Step 2: Buyer (dialer pad phone + voice name)
/// Step 3: Money (token type toggle, amounts, commission)
class NayaDealScreen extends ConsumerStatefulWidget {
  const NayaDealScreen({super.key});

  @override
  ConsumerState<NayaDealScreen> createState() => _NayaDealScreenState();
}

class _NayaDealScreenState extends ConsumerState<NayaDealScreen> {
  int _step = 0;
  String? _selectedPropertyId;
  String? _selectedBuyerId;
  String _buyerPhone = '';
  String _buyerName = '';
  int _dealPriceRs = 0;
  double _commBuyer = 1.0;
  double _commSeller = 1.0;
  bool _saving = false;
  String? _validationError;

  bool _validateStep() {
    switch (_step) {
      case 0:
        // Property is optional — inquiry can exist without property
        return true;
      case 1:
        // Buyer phone is required to create/find the party
        if (_buyerPhone.trim().isEmpty) {
          setState(() => _validationError = 'خریدار کا نمبر درج کریں');
          return false;
        }
        setState(() => _validationError = null);
        return true;
      case 2:
        // Deal price is optional at inquiry stage
        setState(() => _validationError = null);
        return true;
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          ['پراپرٹی', 'خریدار', 'رقم'][_step],
          style: AppTypography.urH2,
        ),
        leading: _step > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_forward_rounded),
                onPressed: () => setState(() => _step--),
              )
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => context.pop(),
              ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_step + 1) / 3,
            backgroundColor: AppColors.ink100,
            color: AppColors.brand600,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_validationError != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.base, vertical: AppSpacing.sm),
                color: AppColors.danger.withAlpha(20),
                child: Text(
                  _validationError!,
                  style: AppTypography.urBody.copyWith(color: AppColors.danger),
                  textAlign: TextAlign.center,
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: _step,
                children: [
                  _Step1Property(
                    selectedId: _selectedPropertyId,
                    onSelected: (id) => setState(() => _selectedPropertyId = id),
                  ),
                  _Step2Buyer(
                    phone: _buyerPhone,
                    name: _buyerName,
                    selectedId: _selectedBuyerId,
                    onPhoneChanged: (v) => setState(() => _buyerPhone = v),
                    onNameChanged: (v) => setState(() => _buyerName = v),
                    onPartySelected: (id) => setState(() => _selectedBuyerId = id),
                  ),
                  _Step3Money(
                    dealPriceRs: _dealPriceRs,
                    commBuyer: _commBuyer,
                    commSeller: _commSeller,
                    onPriceChanged: (v) => setState(() => _dealPriceRs = v),
                    onCommBuyerChanged: (v) => setState(() => _commBuyer = v),
                    onCommSellerChanged: (v) => setState(() => _commSeller = v),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: ElevatedButton(
            onPressed: _saving ? null : _onNext,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
            ),
            child: _saving
                ? const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white))
                : Text(
                    _step < 2 ? 'اگلا' : 'ڈیل شروع کریں',
                    style: AppTypography.urBodyBold,
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _onNext() async {
    if (!_validateStep()) return;

    if (_step < 2) {
      setState(() => _step++);
      return;
    }

    // Step 3: create deal
    setState(() => _saving = true);
    final session = ref.read(currentSessionProvider);
    if (session == null) return;

    try {
      String? buyerId = _selectedBuyerId;

      // Create/find buyer party from phone if not already selected
      if (buyerId == null && _buyerPhone.isNotEmpty) {
        final existing = await ref
            .read(partiesRepositoryProvider)
            .checkDuplicateByPhone(
              dealerId: session.dealerId,
              phone: _buyerPhone.trim(),
            );
        if (existing != null) {
          buyerId = existing.id;
        } else if (_buyerName.isNotEmpty) {
          final party = await ref.read(partiesRepositoryProvider).createParty(
            dealerId: session.dealerId,
            party: Party(
              id: '',
              dealerId: session.dealerId,
              type: PartyType.buyer,
              name: _buyerName.trim(),
              phone: _buyerPhone.trim(),
              waOptIn: false,
              createdAt: DateTime.now(),
            ),
            createdBy: session.userId,
          );
          buyerId = party.id;
        }
      }

      final deal = await ref.read(dealsProvider.notifier).createDeal(
        propertyId: _selectedPropertyId,
        buyerPartyId: buyerId,
        dealPriceRs: _dealPriceRs > 0 ? _dealPriceRs : null,
        commBuyerPct: _commBuyer,
        commSellerPct: _commSeller,
      );

      if (deal != null && mounted) {
        await ref.read(ttsServiceProvider).speak('نیا ڈیل بن گیا');
        HapticFeedback.heavyImpact();
        context.go('${AppRoutes.deals}/${deal.id}');
      }
    } catch (e) {
      setState(() {
        _saving = false;
        _validationError = e.toString();
      });
    }
  }
}

class _Step1Property extends ConsumerWidget {
  final String? selectedId;
  final void Function(String?) onSelected;

  const _Step1Property({this.selectedId, required this.onSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventoryAsync = ref.watch(inventoryProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('پراپرٹی منتخب کریں (اختیاری)',
              style: AppTypography.urH2, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          Text('بغیر پراپرٹی کے بھی ڈیل شروع ہو سکتی ہے',
              style: AppTypography.caption.copyWith(color: AppColors.ink500),
              textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.lg),
          if (selectedId != null)
            Container(
              padding: const EdgeInsets.all(AppSpacing.base),
              decoration: BoxDecoration(
                color: AppColors.success.withAlpha(20),
                borderRadius: AppSpacing.cardRadius,
                border: Border.all(color: AppColors.success.withAlpha(80)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: AppColors.success),
                  const SizedBox(width: AppSpacing.sm),
                  Text('پراپرٹی منتخب ہوئی', style: AppTypography.urBodyMedium),
                  const Spacer(),
                  TextButton(
                    onPressed: () => onSelected(null),
                    child: Text('تبدیل کریں', style: AppTypography.urBody.copyWith(color: AppColors.brand600)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.base),
          inventoryAsync.when(
            loading: () => const ListSkeleton(itemCount: 3, itemHeight: 70),
            error: (_, __) => const SizedBox.shrink(),
            data: (properties) {
              final available = properties
                  .where((p) => p.status == PropertyStatus.available)
                  .take(10)
                  .toList();
              if (available.isEmpty) {
                return Text(
                  'کوئی دستیاب پراپرٹی نہیں',
                  style: AppTypography.caption.copyWith(color: AppColors.ink300),
                  textAlign: TextAlign.center,
                );
              }
              return Column(
                children: available.map((prop) {
                  final isSelected = prop.id == selectedId;
                  return GestureDetector(
                    onTap: () => onSelected(prop.id),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      padding: const EdgeInsets.all(AppSpacing.base),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.brand100
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: AppSpacing.cardRadius,
                        border: Border.all(
                          color: isSelected ? AppColors.brand600 : AppColors.ink100,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.villa_rounded,
                              color: isSelected ? AppColors.brand600 : AppColors.ink500),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(prop.society,
                                    style: AppTypography.urBodyMedium,
                                    textDirection: TextDirection.rtl),
                                if (prop.sizeLabel != null)
                                  Text(prop.sizeLabel!,
                                      style: AppTypography.caption),
                              ],
                            ),
                          ),
                          if (prop.demandRs != null)
                            Text(
                              formatMoney(prop.demandRs!),
                              style: AppTypography.moneySmall.copyWith(
                                  color: AppColors.brand600),
                              textDirection: TextDirection.ltr,
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Step2Buyer extends StatefulWidget {
  final String phone;
  final String name;
  final String? selectedId;
  final void Function(String) onPhoneChanged;
  final void Function(String) onNameChanged;
  final void Function(String?) onPartySelected;

  const _Step2Buyer({
    required this.phone,
    required this.name,
    this.selectedId,
    required this.onPhoneChanged,
    required this.onNameChanged,
    required this.onPartySelected,
  });

  @override
  State<_Step2Buyer> createState() => _Step2BuyerState();
}

class _Step2BuyerState extends State<_Step2Buyer> {
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _phoneCtrl = TextEditingController(text: widget.phone);
    _nameCtrl  = TextEditingController(text: widget.name);
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('خریدار کا نمبر', style: AppTypography.urH2,
              textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            style: AppTypography.moneyLarge.copyWith(letterSpacing: 2),
            decoration: const InputDecoration(
              hintText: '03xx-xxxxxxx',
              prefixIcon: Icon(Icons.phone_rounded, color: AppColors.brand600),
            ),
            onChanged: widget.onPhoneChanged,
          ),
          const SizedBox(height: AppSpacing.base),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  textDirection: TextDirection.rtl,
                  style: AppTypography.urBodyMedium,
                  decoration: InputDecoration(
                    labelText: 'نام (اختیاری)',
                    labelStyle: AppTypography.urLabel,
                  ),
                  onChanged: widget.onNameChanged,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: AppColors.brand100,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic_rounded, color: AppColors.brand600),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.base),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('واٹس ایپ اجازت', style: AppTypography.urBodyMedium),
              Switch(
                value: true,
                onChanged: (_) {},
                activeColor: AppColors.brand600,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Step3Money extends StatelessWidget {
  final int dealPriceRs;
  final double commBuyer;
  final double commSeller;
  final void Function(int) onPriceChanged;
  final void Function(double) onCommBuyerChanged;
  final void Function(double) onCommSellerChanged;

  const _Step3Money({
    required this.dealPriceRs,
    required this.commBuyer,
    required this.commSeller,
    required this.onPriceChanged,
    required this.onCommBuyerChanged,
    required this.onCommSellerChanged,
  });

  int get _expectedComm =>
      ((dealPriceRs * (commBuyer + commSeller)) / 100).round();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('رقم درج کریں', style: AppTypography.urH2,
              textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.base),

          // Deal price number pad
          NumberPad(
            initialAmount: dealPriceRs,
            onAmountChanged: onPriceChanged,
          ),

          const SizedBox(height: AppSpacing.lg),

          // Commission sliders
          _CommRow(
            label: 'خریدار کمیشن',
            pct: commBuyer,
            onChanged: onCommBuyerChanged,
          ),
          const SizedBox(height: AppSpacing.sm),
          _CommRow(
            label: 'فروخت کنندہ کمیشن',
            pct: commSeller,
            onChanged: onCommSellerChanged,
          ),

          if (_expectedComm > 0) ...[
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.base),
              decoration: BoxDecoration(
                color: AppColors.success.withAlpha(15),
                borderRadius: AppSpacing.cardRadius,
                border: Border.all(color: AppColors.success.withAlpha(60)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('توقع کمیشن', style: AppTypography.urBodyMedium),
                  Text(
                    formatMoney(_expectedComm),
                    style: AppTypography.moneyMedium.copyWith(
                        color: AppColors.success),
                    textDirection: TextDirection.ltr,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CommRow extends StatelessWidget {
  final String label;
  final double pct;
  final void Function(double) onChanged;

  const _CommRow({
    required this.label,
    required this.pct,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: AppTypography.urBodyMedium),
        ),
        SizedBox(
          width: 140,
          child: Slider(
            value: pct,
            min: 0,
            max: 3,
            divisions: 12,
            label: '${pct.toStringAsFixed(1)}%',
            activeColor: AppColors.brand600,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '${pct.toStringAsFixed(1)}%',
            style: AppTypography.moneySmall,
            textDirection: TextDirection.ltr,
          ),
        ),
      ],
    );
  }
}
