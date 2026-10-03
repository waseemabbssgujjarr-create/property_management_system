import 'package:equatable/equatable.dart';
import '../../inventory/models/property_models.dart';
import '../../parties/models/party_models.dart';

// Re-export DealStage from stage_strip so all deal code uses one enum
export '../../../widgets/deal/stage_strip.dart' show DealStage;

enum TokenType {
  conditional, confirmed;

  String get dbValue => name;
  String get labelUr => switch (this) {
    TokenType.conditional => 'مشروط ٹوکن',
    TokenType.confirmed   => 'پکا ٹوکن',
  };
  String get descriptionUr => switch (this) {
    TokenType.conditional =>
      'واپسی ہو سکتی ہے — کاغذات کی تصدیق کے بعد پکا ہوگا',
    TokenType.confirmed   =>
      'اگر خریدار پیچھے ہٹے تو ٹوکن ضبط، فروخت کنندہ پیچھے ہٹے تو دگنا واپس',
  };
  static TokenType? fromDb(String? v) => switch (v) {
    'conditional' => TokenType.conditional,
    'confirmed'   => TokenType.confirmed,
    _             => null,
  };
}

enum LostReason {
  price, foundElsewhere, coldFeet, financing, other;

  String get dbValue => switch (this) {
    LostReason.price          => 'price',
    LostReason.foundElsewhere => 'found_elsewhere',
    LostReason.coldFeet       => 'cold_feet',
    LostReason.financing      => 'financing',
    LostReason.other          => 'other',
  };
  String get labelUr => switch (this) {
    LostReason.price          => 'قیمت',
    LostReason.foundElsewhere => 'دوسری جگہ مل گئی',
    LostReason.coldFeet       => 'ارادہ بدل گیا',
    LostReason.financing      => 'فنانسنگ نہیں ہوئی',
    LostReason.other          => 'دیگر',
  };
  static LostReason? fromDb(String? v) => switch (v) {
    'price'           => LostReason.price,
    'found_elsewhere' => LostReason.foundElsewhere,
    'cold_feet'       => LostReason.coldFeet,
    'financing'       => LostReason.financing,
    _                 => v != null ? LostReason.other : null,
  };
}

class Deal extends Equatable {
  final String id;
  final String dealerId;
  final String? officeId;
  final String? propertyId;
  final String? buyerPartyId;
  final String? sellerPartyId;
  final String? assignedAgentId;

  // Stage
  final DealStage stage;

  // Token
  final TokenType? tokenType;
  final int? tokenRs;
  final DateTime? tokenDate;
  final DateTime? tokenExpiresAt;
  final String? tokenTermsText;
  final String? tokenTermsAudioUrl;

  // Bayana
  final int? bayanaRs;
  final DateTime? bayanaDate;
  final DateTime? bayanaDueAt;

  // Financials
  final int? dealPriceRs;
  final double commBuyerPct;
  final double commSellerPct;
  final int? expectedCommRs;    // generated column from DB

  // Registry
  final DateTime? registryExpectedAt;
  final DateTime? registryCompletedAt;
  final String? registryRef;

  // Outcome
  final LostReason? lostReason;
  final String? lostNote;

  final String? notesText;
  final String? notesAudioUrl;
  final DateTime? closedAt;
  final DateTime createdAt;

  // Populated via join (nullable until loaded)
  final Property? property;
  final Party? buyer;
  final Party? seller;

  const Deal({
    required this.id,
    required this.dealerId,
    this.officeId,
    this.propertyId,
    this.buyerPartyId,
    this.sellerPartyId,
    this.assignedAgentId,
    this.stage = DealStage.inquiry,
    this.tokenType,
    this.tokenRs,
    this.tokenDate,
    this.tokenExpiresAt,
    this.tokenTermsText,
    this.tokenTermsAudioUrl,
    this.bayanaRs,
    this.bayanaDate,
    this.bayanaDueAt,
    this.dealPriceRs,
    this.commBuyerPct = 1.0,
    this.commSellerPct = 1.0,
    this.expectedCommRs,
    this.registryExpectedAt,
    this.registryCompletedAt,
    this.registryRef,
    this.lostReason,
    this.lostNote,
    this.notesText,
    this.notesAudioUrl,
    this.closedAt,
    required this.createdAt,
    this.property,
    this.buyer,
    this.seller,
  });

  int get daysInStage {
    return DateTime.now().difference(createdAt).inDays;
  }

  bool get isStale => daysInStage > 7 && !stage.isTerminal;

  int? get tokenDaysRemaining {
    if (tokenExpiresAt == null) return null;
    return tokenExpiresAt!.difference(DateTime.now()).inDays;
  }

  bool get tokenUrgent {
    final days = tokenDaysRemaining;
    return days != null && days <= 3;
  }

  factory Deal.fromMap(Map<String, dynamic> m) => Deal(
    id: m['id'] as String,
    dealerId: m['dealer_id'] as String,
    officeId: m['office_id'] as String?,
    propertyId: m['property_id'] as String?,
    buyerPartyId: m['buyer_party_id'] as String?,
    sellerPartyId: m['seller_party_id'] as String?,
    assignedAgentId: m['assigned_agent_id'] as String?,
    stage: DealStage.fromDb(m['stage'] as String?) ?? DealStage.inquiry,
    tokenType: TokenType.fromDb(m['token_type'] as String?),
    tokenRs: m['token_rs'] as int?,
    tokenDate: m['token_date'] != null
        ? DateTime.tryParse(m['token_date'] as String)
        : null,
    tokenExpiresAt: m['token_expires_at'] != null
        ? DateTime.tryParse(m['token_expires_at'] as String)
        : null,
    tokenTermsText: m['token_terms_text'] as String?,
    tokenTermsAudioUrl: m['token_terms_audio_url'] as String?,
    bayanaRs: m['bayana_rs'] as int?,
    bayanaDate: m['bayana_date'] != null
        ? DateTime.tryParse(m['bayana_date'] as String)
        : null,
    bayanaDueAt: m['bayana_due_at'] != null
        ? DateTime.tryParse(m['bayana_due_at'] as String)
        : null,
    dealPriceRs: m['deal_price_rs'] as int?,
    commBuyerPct: (m['comm_buyer_pct'] as num?)?.toDouble() ?? 1.0,
    commSellerPct: (m['comm_seller_pct'] as num?)?.toDouble() ?? 1.0,
    expectedCommRs: m['expected_comm_rs'] as int?,
    registryExpectedAt: m['registry_expected_at'] != null
        ? DateTime.tryParse(m['registry_expected_at'] as String)
        : null,
    registryCompletedAt: m['registry_completed_at'] != null
        ? DateTime.tryParse(m['registry_completed_at'] as String)
        : null,
    registryRef: m['registry_ref'] as String?,
    lostReason: LostReason.fromDb(m['lost_reason'] as String?),
    lostNote: m['lost_note'] as String?,
    notesText: m['notes_text'] as String?,
    notesAudioUrl: m['notes_audio_url'] as String?,
    closedAt: m['closed_at'] != null
        ? DateTime.tryParse(m['closed_at'] as String)
        : null,
    createdAt: DateTime.parse(m['created_at'] as String),
  );

  @override
  List<Object?> get props => [id, stage, tokenExpiresAt, dealPriceRs];
}

class DealEvent extends Equatable {
  final String id;
  final String dealId;
  final String kind;
  final String? fromStage;
  final String? toStage;
  final String? actorId;
  final DateTime occurredAt;
  final Map<String, dynamic> meta;

  const DealEvent({
    required this.id,
    required this.dealId,
    required this.kind,
    this.fromStage,
    this.toStage,
    this.actorId,
    required this.occurredAt,
    this.meta = const {},
  });

  factory DealEvent.fromMap(Map<String, dynamic> m) => DealEvent(
    id: m['id'] as String,
    dealId: m['deal_id'] as String,
    kind: m['kind'] as String,
    fromStage: m['from_stage'] as String?,
    toStage: m['to_stage'] as String?,
    actorId: m['actor_id'] as String?,
    occurredAt: DateTime.parse(m['occurred_at'] as String),
    meta: (m['meta'] as Map?)?.cast<String, dynamic>() ?? {},
  );

  @override
  List<Object?> get props => [id, occurredAt];
}

class DealSplit extends Equatable {
  final String id;
  final String dealId;
  final String userId;
  final String dealerId;
  final double pct;
  final int paidRs;
  int? earnedRs; // computed: expectedComm * pct / 100

  DealSplit({
    required this.id,
    required this.dealId,
    required this.userId,
    required this.dealerId,
    required this.pct,
    this.paidRs = 0,
    this.earnedRs,
  });

  int get pendingRs => (earnedRs ?? 0) - paidRs;

  factory DealSplit.fromMap(Map<String, dynamic> m) => DealSplit(
    id: m['id'] as String,
    dealId: m['deal_id'] as String,
    userId: m['user_id'] as String,
    dealerId: m['dealer_id'] as String,
    pct: (m['pct'] as num).toDouble(),
    paidRs: m['paid_rs'] as int? ?? 0,
    earnedRs: m['earned_rs'] as int?,
  );

  @override
  List<Object?> get props => [id, pct, paidRs];
}
