import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/models/account_holding.dart';
import 'package:sure_mobile/utils/investment_math.dart';

AccountHolding _holding({
  String quantity = '10.0',
  String amount = r'$1,200.00',
  String? avgCost = r'$100.00',
}) =>
    AccountHolding(
      id: 'h1',
      date: DateTime(2026, 11, 10),
      quantity: quantity,
      price: r'$120.00',
      amount: amount,
      currency: 'USD',
      avgCost: avgCost,
    );

void main() {
  group('InvestmentMath.gainFor', () {
    test('computes unrealized gain against cost basis', () {
      final gain = InvestmentMath.gainFor(_holding())!;
      expect(gain.amount, closeTo(200, 0.001));
      expect(gain.percent, closeTo(0.2, 0.0001));
      expect(gain.isLoss, false);
    });

    test('reports losses', () {
      final gain = InvestmentMath.gainFor(_holding(amount: r'$800.00'))!;
      expect(gain.amount, closeTo(-200, 0.001));
      expect(gain.isLoss, true);
    });

    test('returns null without a cost basis', () {
      expect(InvestmentMath.gainFor(_holding(avgCost: null)), isNull);
      expect(InvestmentMath.gainFor(_holding(avgCost: r'$0.00')), isNull);
    });
  });

  group('InvestmentMath formatting', () {
    test('formats signed money and percentages', () {
      expect(
        InvestmentMath.formatMoney(1204, currency: 'USD', locale: 'en_US',
            signed: true),
        r'+$1,204.00',
      );
      expect(
        InvestmentMath.formatMoney(-5, currency: 'USD', locale: 'en_US',
            signed: true),
        r'-$5.00',
      );
      expect(InvestmentMath.formatPercent(0.014, locale: 'en_US'), '+1.4%');
      expect(InvestmentMath.formatPercent(-0.2, locale: 'en_US'), '-20.0%');
    });

    test('trims trailing zeros from quantities', () {
      expect(InvestmentMath.formatQuantity('12.500000', locale: 'en_US'),
          '12.5');
      expect(InvestmentMath.formatQuantity('1200.0', locale: 'en_US'),
          '1,200');
      expect(InvestmentMath.formatQuantity('0.12345678', locale: 'en_US'),
          '0.1235');
    });

    test('converts minor units using the currency precision', () {
      expect(InvestmentMath.fromMinorUnits(123456, currency: 'USD'), 1234.56);
      expect(InvestmentMath.fromMinorUnits(1234, currency: 'JPY'), 1234);
    });
  });
}
