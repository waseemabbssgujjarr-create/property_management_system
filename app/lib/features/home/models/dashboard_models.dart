import 'package:equatable/equatable.dart';

class DashboardSummary extends Equatable {
  final int expectedCommissionRs;
  final int commissionReceivedRs;
  final int todayMoneyIn;
  final int todayMoneyOut;
  final List<ExpiringToken> expiringTokens;
  final List<DueTodayFollowup> followupsDueToday;
  final Map<String, int> stageCounts;
  final DateTime generatedAt;

  const DashboardSummary({
    required this.expectedCommissionRs,
    required this.commissionReceivedRs,
    required this.todayMoneyIn,
    required this.todayMoneyOut,
    required this.expiringTokens,
    required this.followupsDueToday,
    required this.stageCounts,
    required this.generatedAt,
  });

  int get stageInquiry  => stageCounts['inquiry']  ?? 0;
  int get stageToken    => stageCounts['token']    ?? 0;
  int get stageBayana   => stageCounts['bayana']   ?? 0;
  int get stageRegistry => stageCounts['registry'] ?? 0;

  @override
  List<Object?> get props => [
    expectedCommissionRs, commissionReceivedRs,
    expiringTokens.length, followupsDueToday.length, generatedAt,
  ];
}

class ExpiringToken extends Equatable {
  final String dealId;
  final int? dealPriceRs;
  final int? expectedCommRs;
  final DateTime? tokenExpiresAt;
  final String? buyerPartyId;
  final String? propertyId;

  const ExpiringToken({
    required this.dealId,
    this.dealPriceRs,
    this.expectedCommRs,
    this.tokenExpiresAt,
    this.buyerPartyId,
    this.propertyId,
  });

  factory ExpiringToken.fromMap(Map<String, dynamic> m) => ExpiringToken(
    dealId: m['id'] as String,
    dealPriceRs: m['deal_price_rs'] as int?,
    expectedCommRs: m['expected_comm_rs'] as int?,
    tokenExpiresAt: m['token_expires_at'] != null
        ? DateTime.tryParse(m['token_expires_at'] as String)
        : null,
    buyerPartyId: m['buyer_party_id'] as String?,
    propertyId: m['property_id'] as String?,
  );

  int get daysUntilExpiry {
    if (tokenExpiresAt == null) return 0;
    return tokenExpiresAt!.difference(DateTime.now()).inDays;
  }

  bool get isUrgent => daysUntilExpiry <= 1;

  @override
  List<Object?> get props => [dealId, tokenExpiresAt];
}

class DueTodayFollowup extends Equatable {
  final String id;
  final String? partyId;
  final String kind;
  final DateTime dueAt;
  final String? noteText;

  const DueTodayFollowup({
    required this.id,
    this.partyId,
    required this.kind,
    required this.dueAt,
    this.noteText,
  });

  factory DueTodayFollowup.fromMap(Map<String, dynamic> m) => DueTodayFollowup(
    id: m['id'] as String,
    partyId: m['party_id'] as String?,
    kind: m['kind'] as String? ?? 'call',
    dueAt: DateTime.parse(m['due_at'] as String),
    noteText: m['note_text'] as String?,
  );

  @override
  List<Object?> get props => [id, dueAt];
}
