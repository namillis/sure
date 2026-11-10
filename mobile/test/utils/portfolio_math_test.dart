import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/models/account_balance.dart';
import 'package:sure_mobile/models/account_holding.dart';
import 'package:sure_mobile/utils/portfolio_math.dart';

AccountBalance _balance(int day, int cents) => AccountBalance(
      id: 'b$day',
      date: DateTime(2026, 11, day),
      currency: 'USD',
      balance: '\$${cents ~/ 100}',
      balanceCents: cents,
    );

AccountHolding _holding(
  String ticker,
  String amount, {
  String quantity = '1',
  String? avgCost,
}) =>
    AccountHolding(
      id: ticker,
      date: DateTime(2026, 11, 10),
      quantity: quantity,
      price: r'$1.00',
      amount: amount,
      currency: 'USD',
      ticker: ticker,
      avgCost: avgCost,
    );

void main() {
  group('PortfolioMath.sumHistories', () {
    test('adds accounts per day and carries missing days forward', () {
      final summed = PortfolioMath.sumHistories(
        [
          [_balance(1, 10000), _balance(2, 11000), _balance(3, 12000)],
          // Starts a day later and skips day 3.
          [_balance(2, 500), _balance(4, 700)],
        ],
        currency: 'USD',
        locale: 'en_US',
      );

      expect(summed.map((b) => b.date.day), [1, 2, 3, 4]);
      expect(summed.map((b) => b.balanceCents), [10000, 11500, 12500, 12700]);
      expect(summed.last.balance, r'$127.00');
    });

    test('ignores rows without minor units and returns empty for no data',
        () {
      final summed = PortfolioMath.sumHistories(
        [
          [
            AccountBalance(
              id: 'x',
              date: DateTime(2026, 11, 1),
              currency: 'USD',
              balance: r'$1',
            ),
          ],
        ],
        currency: 'USD',
      );
      expect(summed, isEmpty);
    });
  });

  group('PortfolioMath.totalGain', () {
    test('sums gain and cost basis over holdings that have one', () {
      final gain = PortfolioMath.totalGain([
        _holding('A', r'$120.00', quantity: '10', avgCost: r'$10.00'),
        _holding('B', r'$80.00', quantity: '10', avgCost: r'$10.00'),
        _holding('C', r'$500.00'), // no cost basis: left out
        _holding('D', r'$50.00', quantity: '5', avgCost: r'$10.00'), // 0 gain
      ])!;

      // cost 100 + 100 + 50 = 250, value 120 + 80 + 50 = 250
      expect(gain.amount, closeTo(0, 0.0001));
      expect(gain.costBasis, closeTo(250, 0.0001));
      expect(gain.percent, closeTo(0, 0.0001));
    });

    test('returns null when no holding has a cost basis', () {
      expect(PortfolioMath.totalGain([_holding('A', r'$5.00')]), isNull);
    });
  });

  group('PortfolioMath.allocation', () {
    test('keeps the top five, groups the rest and appends cash', () {
      final slices = PortfolioMath.allocation(
        [
          for (var i = 1; i <= 7; i++) _holding('T$i', '\$${i * 10}.00'),
          _holding('ZERO', r'$0.00'),
        ],
        cash: 20,
      );

      expect(
        slices.map((s) => s.kind),
        [
          ...List.filled(5, AllocationKind.holding),
          AllocationKind.other,
          AllocationKind.cash,
        ],
      );
      expect(slices.first.label, 'T7');
      expect(slices[5].value, closeTo(30, 0.0001)); // T1 + T2
      const total = 280 + 20;
      expect(slices.last.fraction, closeTo(20 / total, 0.0001));
      expect(slices.fold<double>(0, (sum, s) => sum + s.fraction),
          closeTo(1, 0.0001));
    });

    test('combines one security held in several accounts', () {
      final first = AccountHolding(
        id: 'h1',
        date: DateTime(2026, 11, 10),
        quantity: '1',
        price: r'$1.00',
        amount: r'$100.00',
        currency: 'USD',
        ticker: 'BTC',
        securityId: 'sec_btc',
      );
      final second = AccountHolding(
        id: 'h2',
        date: DateTime(2026, 11, 10),
        quantity: '1',
        price: r'$1.00',
        amount: r'$50.00',
        currency: 'USD',
        ticker: 'BTC',
        securityId: 'sec_btc',
      );

      final slices = PortfolioMath.allocation([first, second]);
      expect(slices, hasLength(1));
      expect(slices.single.value, closeTo(150, 0.0001));
    });

    test('derives cash from account totals minus holdings', () {
      expect(
        PortfolioMath.cash(
          accountsTotal: 300,
          holdings: [_holding('A', r'$120.00'), _holding('B', r'$80.00')],
        ),
        closeTo(100, 0.0001),
      );
      expect(
        PortfolioMath.cash(accountsTotal: 50, holdings: [_holding('A', r'$80.00')]),
        0,
      );
    });

    test('is empty when nothing has value', () {
      expect(PortfolioMath.allocation([_holding('A', r'$0.00')]), isEmpty);
    });
  });

  group('PortfolioMath.change', () {
    test('reports change and percent between first and last balance', () {
      final change =
          PortfolioMath.change([_balance(1, 10000), _balance(2, 12500)])!;
      expect(change.amount, closeTo(25, 0.0001));
      expect(change.percent, closeTo(0.25, 0.0001));
    });

    test('has no percent when the range started at zero', () {
      final change = PortfolioMath.change([_balance(1, 0), _balance(2, 500)])!;
      expect(change.percent, isNull);
    });
  });
}
