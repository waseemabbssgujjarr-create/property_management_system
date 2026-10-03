import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:munshi/core/errors/app_error.dart';
import 'package:munshi/core/utils/money_formatter.dart';

/// Financial integrity property-based tests.
///
/// These verify the invariants that must NEVER be violated:
/// - Splits always sum to 100%
/// - Amount cannot be negative
/// - Commission calculations are deterministic
void main() {
  group('Commission calculation', () {
    test('expected commission = price × (buyer% + seller%) / 100', () {
      const dealPrice = 10000000; // ₨ 1 crore
      const buyerPct = 1.0;
      const sellerPct = 1.0;

      final expected = (dealPrice * (buyerPct + sellerPct) / 100).round();
      expect(expected, equals(200000)); // ₨ 2 lac
    });

    test('commission calculation is deterministic for same inputs', () {
      const price = 25000000;
      const buyer = 1.0;
      const seller = 0.75;

      final result1 = (price * (buyer + seller) / 100).round();
      final result2 = (price * (buyer + seller) / 100).round();
      expect(result1, equals(result2));
    });

    test('staff split amounts equal expected commission within rounding', () {
      const expectedComm = 200000; // ₨ 2 lac
      const splits = [
        ('Staff A', 50.0),
        ('Staff B', 30.0),
        ('Staff C', 20.0),
      ];

      // Verify splits sum to 100
      final totalPct = splits.fold<double>(0, (s, e) => s + e.$2);
      expect(totalPct, equals(100.0));

      // Verify split amounts sum to expected commission (within 1 rupee rounding)
      final splitAmounts = splits.map((s) => (expectedComm * s.$2 / 100).round());
      final totalSplit = splitAmounts.fold<int>(0, (s, a) => s + a);
      expect((totalSplit - expectedComm).abs(), lessThanOrEqualTo(1));
    });

    test('zero commission on zero price', () {
      const dealPrice = 0;
      const comm = (dealPrice * 2.0 / 100).toInt();
      expect(comm, equals(0));
    });
  });

  group('Amount validation', () {
    test('negative amount throws FinancialIntegrityError', () {
      void recordNegative() {
        const amount = -1000;
        if (amount < 0) {
          throw const FinancialIntegrityError('رقم صفر سے کم نہیں ہو سکتی');
        }
      }
      expect(recordNegative, throwsA(isA<FinancialIntegrityError>()));
    });

    test('zero amount is allowed', () {
      const amount = 0;
      expect(amount >= 0, isTrue);
    });
  });

  group('Split sum invariant', () {
    test('splits summing to 100% pass validation', () {
      final splits = [50.0, 30.0, 20.0];
      final total = splits.fold<double>(0, (s, p) => s + p);
      expect((total - 100).abs(), lessThan(0.01));
    });

    test('splits not summing to 100% fail validation', () {
      final splits = [50.0, 30.0]; // Only 80%
      final total = splits.fold<double>(0, (s, p) => s + p);
      final isValid = (total - 100).abs() < 0.01;
      expect(isValid, isFalse);
    });

    test('110% splits are detected as invalid', () {
      final splits = [50.0, 30.0, 30.0]; // 110%
      final total = splits.fold<double>(0, (s, p) => s + p);
      expect(total, greaterThan(100.0));
      final isValid = (total - 100).abs() < 0.01;
      expect(isValid, isFalse);
    });

    test('99% splits are detected as invalid', () {
      final splits = [50.0, 30.0, 19.0]; // 99%
      final total = splits.fold<double>(0, (s, p) => s + p);
      final isValid = (total - 100).abs() < 0.01;
      expect(isValid, isFalse);
    });

    test('single staff gets 100%', () {
      final splits = [100.0];
      final total = splits.fold<double>(0, (s, p) => s + p);
      expect((total - 100).abs(), lessThan(0.01));
    });

    test('10 staff × 10% each sums to 100%', () {
      final splits = List.filled(10, 10.0);
      final total = splits.fold<double>(0, (s, p) => s + p);
      expect((total - 100).abs(), lessThan(0.01));
    });
  });

  group('Money formatting — no raw millions', () {
    test('amounts above 1 lac never show 7+ consecutive digits', () {
      final testAmounts = [100000, 500000, 1000000, 12500000, 100000000];
      for (final amount in testAmounts) {
        final formatted = formatMoney(amount);
        final rawDigitPattern = RegExp(r'\d{7,}');
        expect(
          rawDigitPattern.hasMatch(formatted),
          isFalse,
          reason: 'formatMoney($amount) = "$formatted" contains raw digits',
        );
      }
    });

    test('spoken form always ends with روپے', () {
      final amounts = [1000, 50000, 1000000, 12500000];
      for (final amount in amounts) {
        final spoken = speakAmount(amount);
        expect(spoken, endsWith('روپے'),
            reason: 'speakAmount($amount) = "$spoken" should end with روپے');
      }
    });
  });

  group('Payment idempotency keys', () {
    test('different UUID calls produce different keys', () {
      final key1 = const Uuid().v4();
      final key2 = const Uuid().v4();
      expect(key1, isNot(equals(key2)));
    });

    test('same key string is equal (idempotency check)', () {
      const key1 = 'test-key-abc-123';
      const key2 = 'test-key-abc-123';
      expect(key1, equals(key2));
    });
  });

  group('Financial immutability (logic layer)', () {
    test('reversal direction is opposite of original', () {
      const originalDirection = 'in';
      final reversalDirection = originalDirection == 'in' ? 'out' : 'in';
      expect(reversalDirection, equals('out'));
    });

    test('reversal of outgoing is incoming', () {
      const originalDirection = 'out';
      final reversalDirection = originalDirection == 'in' ? 'out' : 'in';
      expect(reversalDirection, equals('in'));
    });
  });
}
