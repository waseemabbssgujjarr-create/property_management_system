import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/session_provider.dart';
import '../models/deal_models.dart';
import '../repositories/deals_repository.dart';

class DealsNotifier extends AsyncNotifier<List<Deal>> {
  DealStage? _filterStage;

  @override
  Future<List<Deal>> build() async {
    final session = ref.watch(currentSessionProvider);
    if (session == null) return [];
    return ref.read(dealsRepositoryProvider).getDeals(
      dealerId: session.dealerId,
      filterStage: _filterStage,
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  void filterByStage(DealStage? stage) {
    _filterStage = stage;
    ref.invalidateSelf();
  }

  Future<Deal?> createDeal({
    String? propertyId,
    String? buyerPartyId,
    String? sellerPartyId,
    int? dealPriceRs,
    double commBuyerPct = 1.0,
    double commSellerPct = 1.0,
  }) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return null;
    final deal = await ref.read(dealsRepositoryProvider).createDeal(
      dealerId: session.dealerId,
      propertyId: propertyId,
      buyerPartyId: buyerPartyId,
      sellerPartyId: sellerPartyId,
      dealPriceRs: dealPriceRs,
      commBuyerPct: commBuyerPct,
      commSellerPct: commSellerPct,
      createdBy: session.userId,
    );
    ref.invalidateSelf();
    return deal;
  }

  Future<Deal?> advanceStage(
    String dealId,
    DealStage from,
    DealStage to, {
    Map<String, dynamic> stageData = const {},
  }) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return null;
    final updated = await ref.read(dealsRepositoryProvider).advanceStage(
      dealId: dealId,
      dealerId: session.dealerId,
      fromStage: from,
      toStage: to,
      actorId: session.userId,
      stageData: stageData,
    );
    ref.invalidateSelf();
    return updated;
  }
}

final dealsProvider =
    AsyncNotifierProvider<DealsNotifier, List<Deal>>(DealsNotifier.new);

final dealDetailProvider =
    FutureProvider.family<Deal, String>((ref, dealId) async {
  final session = ref.watch(currentSessionProvider);
  if (session == null) throw Exception('Not authenticated');
  return ref.read(dealsRepositoryProvider).getDeal(dealId, session.dealerId);
});

final dealEventsProvider =
    FutureProvider.family<List<DealEvent>, String>((ref, dealId) async {
  final session = ref.watch(currentSessionProvider);
  if (session == null) return [];
  return ref
      .read(dealsRepositoryProvider)
      .getDealEvents(dealId, session.dealerId);
});

final dealSplitsProvider =
    FutureProvider.family<List<DealSplit>, String>((ref, dealId) async {
  final session = ref.watch(currentSessionProvider);
  if (session == null) return [];
  return ref
      .read(dealsRepositoryProvider)
      .getDealSplits(dealId, session.dealerId);
});
