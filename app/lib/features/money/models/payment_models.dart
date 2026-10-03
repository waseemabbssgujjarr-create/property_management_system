import 'package:equatable/equatable.dart';

enum PaymentKind {
  tokenIn, bayanaIn, commissionIn, splitPaid,
  expense, otherIn, otherOut, reversal, adjustment;

  String get dbValue => switch (this) {
    PaymentKind.tokenIn      => 'token_in',
    PaymentKind.bayanaIn     => 'bayana_in',
    PaymentKind.commissionIn => 'commission_in',
    PaymentKind.splitPaid    => 'split_paid',
    PaymentKind.expense      => 'expense',
    PaymentKind.otherIn      => 'other_in',
    PaymentKind.otherOut     => 'other_out',
    PaymentKind.reversal     => 'reversal',
    PaymentKind.adjustment   => 'adjustment',
  };

  String get labelUr => switch (this) {
    PaymentKind.tokenIn      => 'ٹوکن موصول',
    PaymentKind.bayanaIn     => 'بیعانہ موصول',
    PaymentKind.commissionIn => 'کمیشن موصول',
    PaymentKind.splitPaid    => 'حصہ ادا',
    PaymentKind.expense      => 'خرچہ',
    PaymentKind.otherIn      => 'آمدنی',
    PaymentKind.otherOut     => 'ادائیگی',
    PaymentKind.reversal     => 'واپسی',
    PaymentKind.adjustment   => 'ترمیم',
  };

  bool get isIncoming => switch (this) {
    PaymentKind.tokenIn      => true,
    PaymentKind.bayanaIn     => true,
    PaymentKind.commissionIn => true,
    PaymentKind.otherIn      => true,
    _                        => false,
  };

  static PaymentKind fromDb(String v) => switch (v) {
    'token_in'       => PaymentKind.tokenIn,
    'bayana_in'      => PaymentKind.bayanaIn,
    'commission_in'  => PaymentKind.commissionIn,
    'split_paid'     => PaymentKind.splitPaid,
    'expense'        => PaymentKind.expense,
    'other_in'       => PaymentKind.otherIn,
    'other_out'      => PaymentKind.otherOut,
    'reversal'       => PaymentKind.reversal,
    _                => PaymentKind.adjustment,
  };
}

enum ExpenseCategory {
  office, fuel, food, listingFee, salary, other;

  String get dbValue => switch (this) {
    ExpenseCategory.listingFee => 'listing_fee',
    _                          => name,
  };
  String get labelUr => switch (this) {
    ExpenseCategory.office     => 'دفتر',
    ExpenseCategory.fuel       => 'تیل',
    ExpenseCategory.food       => 'کھانا',
    ExpenseCategory.listingFee => 'اشتہار فیس',
    ExpenseCategory.salary     => 'تنخواہ',
    ExpenseCategory.other      => 'دیگر',
  };
  static ExpenseCategory fromDb(String? v) => switch (v) {
    'fuel'        => ExpenseCategory.fuel,
    'food'        => ExpenseCategory.food,
    'listing_fee' => ExpenseCategory.listingFee,
    'salary'      => ExpenseCategory.salary,
    'other'       => ExpenseCategory.other,
    _             => ExpenseCategory.office,
  };
}

class Payment extends Equatable {
  final String id;
  final String dealerId;
  final String? dealId;
  final PaymentKind kind;
  final int amountRs;
  final String direction;  // 'in' | 'out'
  final String? method;    // cash|bank|jazzcash|easypaisa
  final String? refNo;
  final String? receiptNo;
  final String? receiptPhotoUrl;
  final String? paidToUserId;
  final String? category;
  final String? noteText;
  final String? noteAudioUrl;
  final DateTime occurredAt;
  final String idempotencyKey;

  const Payment({
    required this.id,
    required this.dealerId,
    this.dealId,
    required this.kind,
    required this.amountRs,
    required this.direction,
    this.method,
    this.refNo,
    this.receiptNo,
    this.receiptPhotoUrl,
    this.paidToUserId,
    this.category,
    this.noteText,
    this.noteAudioUrl,
    required this.occurredAt,
    required this.idempotencyKey,
  });

  bool get isIncoming => direction == 'in';

  factory Payment.fromMap(Map<String, dynamic> m) => Payment(
    id: m['id'] as String,
    dealerId: m['dealer_id'] as String,
    dealId: m['deal_id'] as String?,
    kind: PaymentKind.fromDb(m['kind'] as String? ?? 'other_in'),
    amountRs: m['amount_rs'] as int? ?? 0,
    direction: m['direction'] as String? ?? 'in',
    method: m['method'] as String?,
    refNo: m['ref_no'] as String?,
    receiptNo: m['receipt_no'] as String?,
    receiptPhotoUrl: m['receipt_photo_url'] as String?,
    paidToUserId: m['paid_to_user_id'] as String?,
    category: m['category'] as String?,
    noteText: m['note_text'] as String?,
    noteAudioUrl: m['note_audio_url'] as String?,
    occurredAt: DateTime.parse(m['occurred_at'] as String),
    idempotencyKey: m['idempotency_key'] as String? ?? '',
  );

  @override
  List<Object?> get props => [id, amountRs, occurredAt];
}
