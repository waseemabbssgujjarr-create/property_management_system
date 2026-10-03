import 'package:flutter_test/flutter_test.dart';
import 'package:munshi/core/utils/money_formatter.dart';

void main() {
  group('MoneyFormatter.format', () {
    test('formats amounts below 1 lac with commas', () {
      expect(MoneyFormatter.format(0),        equals('₨ 0'));
      expect(MoneyFormatter.format(45000),     equals('₨ 45,000'));
      expect(MoneyFormatter.format(99999),     equals('₨ 99,999'));
    });

    test('formats lac amounts correctly', () {
      expect(MoneyFormatter.format(100000),    equals('₨ 1 لاکھ'));
      expect(MoneyFormatter.format(850000),    equals('₨ 8.5 لاکھ'));
      expect(MoneyFormatter.format(8500000),   equals('₨ 85 لاکھ'));
      expect(MoneyFormatter.format(500000),    equals('₨ 5 لاکھ'));
    });

    test('formats crore amounts correctly', () {
      expect(MoneyFormatter.format(10000000),  equals('₨ 1 کروڑ'));
      expect(MoneyFormatter.format(12500000),  equals('₨ 1.25 کروڑ'));
      expect(MoneyFormatter.format(125000000), equals('₨ 12.5 کروڑ'));
      expect(MoneyFormatter.format(100000000), equals('₨ 10 کروڑ'));
    });

    test('never shows raw millions', () {
      expect(MoneyFormatter.format(12500000),  isNot(contains('12500000')));
      expect(MoneyFormatter.format(8500000),   isNot(contains('8500000')));
    });

    test('uses ltr digits only (never Urdu digits)', () {
      // Latin digits 0-9 only
      final formatted = MoneyFormatter.format(12345678);
      for (final ch in formatted.split('')) {
        if (ch.codeUnitAt(0) >= 0x06F0 && ch.codeUnitAt(0) <= 0x06F9) {
          fail('Found Urdu digit in money format: $ch');
        }
      }
    });

    test('handles zero', () {
      expect(MoneyFormatter.format(0), equals('₨ 0'));
    });
  });

  group('MoneyFormatter.toSpokenUrdu', () {
    test('speaks zero', () {
      expect(MoneyFormatter.toSpokenUrdu(0), equals('صفر روپے'));
    });

    test('speaks thousands', () {
      final spoken = MoneyFormatter.toSpokenUrdu(25000);
      expect(spoken, contains('ہزار'));
      expect(spoken, contains('روپے'));
    });

    test('speaks lac amounts', () {
      final spoken = MoneyFormatter.toSpokenUrdu(5000000);
      expect(spoken, contains('لاکھ'));
    });

    test('speaks crore amounts', () {
      final spoken = MoneyFormatter.toSpokenUrdu(10000000);
      expect(spoken, contains('کروڑ'));
    });

    test('speaks crore with lac remainder', () {
      final spoken = MoneyFormatter.toSpokenUrdu(12500000);
      expect(spoken, contains('کروڑ'));
      expect(spoken, contains('لاکھ'));
    });

    test('always ends with روپے', () {
      for (final amount in [1000, 50000, 500000, 12500000]) {
        expect(MoneyFormatter.toSpokenUrdu(amount), endsWith('روپے'));
      }
    });
  });

  group('MoneyFormatter.parse', () {
    test('parses crore format', () {
      expect(MoneyFormatter.parse('1.25 کروڑ'), equals(12500000));
      expect(MoneyFormatter.parse('10 کروڑ'), equals(100000000));
    });

    test('parses lac format', () {
      expect(MoneyFormatter.parse('85 لاکھ'), equals(8500000));
      expect(MoneyFormatter.parse('5 لاکھ'), equals(500000));
    });

    test('parses plain numbers with commas', () {
      expect(MoneyFormatter.parse('45,000'), equals(45000));
    });

    test('parses plain integers', () {
      expect(MoneyFormatter.parse('45000'), equals(45000));
    });

    test('returns null for invalid input', () {
      expect(MoneyFormatter.parse('abc'), isNull);
    });
  });

  group('MoneyFormatter.compact', () {
    test('returns format without symbol', () {
      expect(MoneyFormatter.compact(12500000), isNot(contains('₨')));
      expect(MoneyFormatter.compact(12500000), contains('کروڑ'));
    });
  });

  group('Edge cases', () {
    test('does not crash on very large amounts', () {
      expect(() => MoneyFormatter.format(999999999999), returnsNormally);
    });

    test('does not show trailing zeros in decimal', () {
      expect(MoneyFormatter.format(10000000),  equals('₨ 1 کروڑ'));
      expect(MoneyFormatter.format(5000000),   equals('₨ 50 لاکھ'));
    });
  });
}
