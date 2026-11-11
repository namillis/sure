import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/models/account_balance.dart';
import 'package:sure_mobile/utils/net_worth_history.dart';

AccountBalance _b(String date, int? cents, {String currency = 'USD'}) =>
    AccountBalance(
      id: '$date-$cents',
      date: DateTime.parse(date),
      currency: currency,
      balance: '$cents',
      balanceCents: cents,
    );

NetWorthAccountHistory _account(
  String id,
  List<AccountBalance> balances, {
  String currency = 'USD',
  bool liability = false,
  int? current,
}) =>
    NetWorthAccountHistory(
      accountId: id,
      currency: currency,
      isLiability: liability,
      currentCents: current,
      balances: balances,
    );

List<int> _cents(NetWorthHistory h) => h.points.map((p) => p.cents).toList();

void main() {
  final start = DateTime(2026, 10, 1);
  final end = DateTime(2026, 10, 5);

  NetWorthHistory build(List<NetWorthAccountHistory> accounts,
          {DateTime? from, DateTime? to}) =>
      NetWorthHistory.build(
        accounts: accounts,
        mainCurrency: 'USD',
        start: from ?? start,
        end: to ?? end,
      );

  test('one point per day, carrying balances forward over gaps', () {
    final h = build([
      _account('a', [
        _b('2026-10-01', 1000),
        _b('2026-10-03', 1500),
      ]),
    ]);
    expect(h.points.first.date, DateTime(2026, 10, 1));
    expect(h.points.last.date, DateTime(2026, 10, 5));
    expect(_cents(h), [1000, 1000, 1500, 1500, 1500]);
    expect(h.currentCents, 1500);
    expect(h.changeCents, 500);
  });

  test('accepts balances in any order (the API is newest first)', () {
    final h = build([
      _account('a', [
        _b('2026-10-04', 300),
        _b('2026-10-01', 100),
        _b('2026-10-02', 200),
      ]),
    ]);
    expect(_cents(h), [100, 200, 200, 300, 300]);
  });

  test('an account opening mid-period adds nothing before its first row', () {
    final h = build([
      _account('a', [_b('2026-10-01', 1000)]),
      _account('b', [_b('2026-10-03', 250), _b('2026-10-04', 400)]),
    ]);
    expect(_cents(h), [1000, 1000, 1250, 1400, 1400]);
  });

  test('liabilities are subtracted', () {
    final h = build([
      _account('cash', [_b('2026-10-01', 5000)]),
      _account('card', [_b('2026-10-01', 1200), _b('2026-10-02', 1800)],
          liability: true),
    ]);
    expect(_cents(h), [3800, 3200, 3200, 3200, 3200]);
    expect(h.changeCents, -600);
  });

  test('other currencies stay off the line and are totaled per currency',
      () {
    final h = build([
      _account('usd', [_b('2026-10-01', 100)]),
      _account('gbp1', [_b('2026-10-01', 999, currency: 'GBP')],
          currency: 'GBP', current: 1000000),
      _account('gbp2', const [], currency: 'GBP', current: 234000),
      _account('gbpLoan', const [],
          currency: 'GBP', current: 10000, liability: true),
      _account('eur', const [], currency: 'EUR', current: 5000),
    ]);
    expect(_cents(h), [100, 100, 100, 100, 100]);
    expect(h.otherCurrencies.map((c) => c.currency), ['EUR', 'GBP']);
    final gbp = h.otherCurrencies.last;
    expect(gbp.cents, 1000000 + 234000 - 10000);
    expect(gbp.accountCount, 3);
    expect(h.otherCurrencies.first.accountCount, 1);
  });

  test('ignores rows in a currency other than the account and null cents',
      () {
    final h = build([
      _account('a', [
        _b('2026-10-01', 100),
        _b('2026-10-02', 99999, currency: 'EUR'),
        _b('2026-10-03', null),
      ]),
    ]);
    expect(_cents(h), [100, 100, 100, 100, 100]);
  });

  test('a main-currency account with no rows uses its current balance', () {
    final h = build([
      _account('a', [_b('2026-10-02', 100)]),
      _account('manual', const [], current: 50),
    ]);
    expect(_cents(h), [50, 150, 150, 150, 150]);
  });

  test('rows after the end are ignored; rows before the start seed day one',
      () {
    final h = build([
      _account('a', [
        _b('2026-09-29', 10),
        _b('2026-09-30', 20),
        _b('2026-10-02', 30),
        _b('2026-10-09', 999),
      ]),
    ]);
    expect(_cents(h), [20, 30, 30, 30, 30]);
  });

  test('empty input gives no points and no change', () {
    final h = build(const []);
    expect(h.points, isEmpty);
    expect(h.currentCents, isNull);
    expect(h.changeCents, isNull);
    expect(h.otherCurrencies, isEmpty);
  });

  test('accounts without any data give no points', () {
    final h = build([_account('a', const [])]);
    expect(h.points, isEmpty);
  });

  test('only other currencies: no line, but the totals are listed', () {
    final h = build([
      _account('g', const [], currency: 'GBP', current: 100),
    ]);
    expect(h.points, isEmpty);
    expect(h.otherCurrencies.single.cents, 100);
  });

  test('an end before the start gives no points', () {
    final h = build([
      _account('a', [_b('2026-10-01', 1)]),
    ], from: DateTime(2026, 10, 5), to: DateTime(2026, 10, 1));
    expect(h.points, isEmpty);
  });

  test('a single day has a value but no change', () {
    final h = build([
      _account('a', [_b('2026-10-01', 1)]),
    ], to: DateTime(2026, 10, 1));
    expect(_cents(h), [1]);
    expect(h.changeCents, isNull);
  });

  test('day count is not skewed by a DST change', () {
    final h = build([
      _account('a', [_b('2026-03-01', 1)]),
    ], from: DateTime(2026, 3, 1), to: DateTime(2026, 3, 31));
    expect(h.points.length, 31);
    expect(h.points.last.date, DateTime(2026, 3, 31));
  });
}
