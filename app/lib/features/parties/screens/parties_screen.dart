import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../widgets/shared/empty_state.dart';
import '../../../widgets/shared/error_state.dart';
import '../../../widgets/shared/skeleton_loader.dart';
import '../../auth/providers/session_provider.dart';
import '../models/party_models.dart';
import '../repositories/parties_repository.dart';

/// Parties screen — buyers & sellers as contact cards.
/// Big call + WhatsApp buttons (no reading required).
/// WhatsApp opt-in = big toggle per party.
class PartiesScreen extends ConsumerStatefulWidget {
  const PartiesScreen({super.key});

  @override
  ConsumerState<PartiesScreen> createState() => _PartiesScreenState();
}

class _PartiesScreenState extends ConsumerState<PartiesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  PartyType _currentType = PartyType.buyer;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      setState(() {
        _currentType = [PartyType.buyer, PartyType.seller, PartyType.investor][_tabCtrl.index];
      });
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentSessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('کلائنٹ', style: AppTypography.urH2),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: [
            Tab(child: Text('خریدار', style: AppTypography.urBodyMedium)),
            Tab(child: Text('فروخت', style: AppTypography.urBodyMedium)),
            Tab(child: Text('سرمایہ', style: AppTypography.urBodyMedium)),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => context.go(AppRoutes.search),
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            onPressed: () => _showAddParty(context, ref),
            icon: const Icon(Icons.person_add_rounded),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _PartiesList(dealerId: session?.dealerId ?? '', type: PartyType.buyer),
          _PartiesList(dealerId: session?.dealerId ?? '', type: PartyType.seller),
          _PartiesList(dealerId: session?.dealerId ?? '', type: PartyType.investor),
        ],
      ),
    );
  }

  void _showAddParty(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddPartySheet(
        defaultType: _currentType,
        onSaved: (party) => ref.invalidate(partiesRepositoryProvider),
      ),
    );
  }
}

class _PartiesList extends ConsumerWidget {
  final String dealerId;
  final PartyType type;

  const _PartiesList({required this.dealerId, required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partiesAsync = ref.watch(_partiesProvider(
      _PartiesParams(dealerId: dealerId, type: type),
    ));

    return partiesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.base),
        child: ListSkeleton(itemCount: 5),
      ),
      error: (e, _) => ErrorState.generic(
        onRetry: () => ref.invalidate(_partiesProvider(
          _PartiesParams(dealerId: dealerId, type: type),
        )),
      ),
      data: (parties) => parties.isEmpty
          ? EmptyState(
              icon: Icons.person_outline_rounded,
              messageUr: 'کوئی ${type.labelUr} نہیں',
              ctaLabelUr: 'شامل کریں',
              speakText: 'کوئی ${type.labelUr} نہیں — شامل کریں',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.base),
              itemCount: parties.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) => _PartyCard(party: parties[i]),
            ),
    );
  }
}

// Inline provider for parties per type
final _partiesProvider = FutureProvider.family<List<Party>, _PartiesParams>(
  (ref, params) async {
    return ref.read(partiesRepositoryProvider).getParties(
      dealerId: params.dealerId,
      filterType: params.type,
    );
  },
);

class _PartiesParams {
  final String dealerId;
  final PartyType type;
  const _PartiesParams({required this.dealerId, required this.type});
  @override
  bool operator ==(Object other) =>
      other is _PartiesParams &&
      other.dealerId == dealerId &&
      other.type == type;
  @override
  int get hashCode => Object.hash(dealerId, type);
}

class _PartyCard extends StatelessWidget {
  final Party party;
  const _PartyCard({required this.party});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('${AppRoutes.parties}/${party.id}'),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: AppSpacing.cardRadius,
          boxShadow: AppElevation.low,
        ),
        child: Row(
          children: [
            // Avatar
            _PartyAvatar(party: party),
            const SizedBox(width: AppSpacing.base),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    party.name,
                    style: AppTypography.urBodyMedium,
                    textDirection: TextDirection.rtl,
                  ),
                  if (party.phone != null)
                    Text(
                      party.phone!,
                      style: AppTypography.caption,
                      textDirection: TextDirection.ltr,
                    ),
                  Row(
                    children: [
                      _SourceChip(source: party.source),
                      if (party.waOptIn) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chat_rounded,
                          size: 14,
                          color: Color(0xFF25D366),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Call button
            if (party.phone != null)
              _ActionButton(
                icon: Icons.phone_rounded,
                color: AppColors.success,
                onTap: () async {
                  final uri = Uri(scheme: 'tel', path: party.phone!);
                  if (await canLaunchUrl(uri)) await launchUrl(uri);
                },
                tooltip: 'کال کریں',
              ),
          ],
        ),
      ),
    );
  }
}

class _PartyAvatar extends StatelessWidget {
  final Party party;
  const _PartyAvatar({required this.party});

  @override
  Widget build(BuildContext context) {
    if (party.photoUrl != null) {
      return CircleAvatar(
        radius: 26,
        backgroundImage: NetworkImage(party.photoUrl!),
      );
    }
    return CircleAvatar(
      radius: 26,
      backgroundColor: AppColors.brand100,
      child: Text(
        party.initials,
        style: AppTypography.urBodyBold.copyWith(color: AppColors.brand600),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          margin: const EdgeInsets.only(right: AppSpacing.sm),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  final PartySource source;
  const _SourceChip({required this.source});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.brand50,
        borderRadius: AppSpacing.pillRadius,
      ),
      child: Text(
        source.labelUr,
        style: const TextStyle(
          fontSize: 10,
          fontFamily: 'NotoNaskhArabic',
          color: AppColors.brand600,
        ),
      ),
    );
  }
}

/// Add party bottom sheet — voice-name capture, dial-pad phone entry.
class _AddPartySheet extends ConsumerStatefulWidget {
  final PartyType defaultType;
  final void Function(Party)? onSaved;

  const _AddPartySheet({required this.defaultType, this.onSaved});

  @override
  ConsumerState<_AddPartySheet> createState() => _AddPartySheetState();
}

class _AddPartySheetState extends ConsumerState<_AddPartySheet> {
  PartyType _type = PartyType.buyer;
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  PartySource _source = PartySource.walkin;
  bool _waOptIn = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _type = widget.defaultType;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    final session = ref.read(currentSessionProvider);
    if (session == null) return;

    setState(() => _saving = true);

    try {
      final party = Party(
        id: '',
        dealerId: session.dealerId,
        type: _type,
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isNotEmpty ? _phoneCtrl.text.trim() : null,
        source: _source,
        waOptIn: _waOptIn,
        waOptInAt: _waOptIn ? DateTime.now() : null,
        createdAt: DateTime.now(),
      );

      final created = await ref.read(partiesRepositoryProvider).createParty(
        dealerId: session.dealerId,
        party: party,
        createdBy: session.userId,
      );

      widget.onSaved?.call(created);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString(), style: AppTypography.urBody),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
        left: AppSpacing.base,
        right: AppSpacing.base,
        top: AppSpacing.base,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('نیا کلائنٹ', style: AppTypography.urH2, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.base),

            // Type selector
            Row(
              children: PartyType.values.map((t) {
                final selected = t == _type;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _type = t),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.brand600 : AppColors.brand50,
                        borderRadius: AppSpacing.buttonRadius,
                      ),
                      child: Text(
                        t.labelUr,
                        style: AppTypography.urBodyMedium.copyWith(
                          color: selected ? Colors.white : AppColors.brand600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: AppSpacing.base),

            // Name field — text + voice mic
            TextField(
              controller: _nameCtrl,
              textDirection: TextDirection.rtl,
              style: AppTypography.urBodyMedium,
              decoration: InputDecoration(
                labelText: 'نام',
                labelStyle: AppTypography.urLabel,
                suffixIcon: const Icon(Icons.mic_rounded, color: AppColors.brand600),
              ),
            ),

            const SizedBox(height: AppSpacing.sm),

            // Phone field
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              style: AppTypography.moneyMedium,
              decoration: const InputDecoration(
                labelText: 'فون نمبر',
                hintText: '03xx-xxxxxxx',
              ),
            ),

            const SizedBox(height: AppSpacing.sm),

            // WhatsApp opt-in toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('واٹس ایپ اجازت', style: AppTypography.urBodyMedium),
                Switch(
                  value: _waOptIn,
                  onChanged: (v) => setState(() => _waOptIn = v),
                  activeColor: AppColors.brand600,
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.lg),

            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
              child: _saving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text('محفوظ کریں', style: AppTypography.urBodyBold),
            ),
            const SizedBox(height: AppSpacing.base),
          ],
        ),
      ),
    );
  }
}
