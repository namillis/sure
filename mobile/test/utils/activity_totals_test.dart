import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/models/activity_transaction.dart';
import 'package:sure_mobile/utils/activity_totals.dart';

ActivityTransaction _row({
  String amount = r'$10.00',
  String? decimal,
  String currency = 'USD',
  bool splitParent = false,
  bool excluded = false,
  Map<String, dynamic>? transfer,
}) =>
    ActivityTransaction.fromJson({
      'id': 'x',
      'date': '2026-11-10',
      'amount': amount,
      if (decimal != null) 'amount_decimal': decimal,
      'currency': currency,
      'name': 'Row',
      'classification': 'expense',
      'split_parent': splitParent,
      'excluded': excluded,
      'account': {'id': 'a', 'name': 'Checking', 'account_type': 'depository'},
      'transfer': transfer,
    });

void main() {
  test('sums money in and out in the entry sign convention', () {
    final totals = ActivityTotals.of([
      _row(decimal: '12.5'),
      _row(decimal: '-100'),
      _row(amount: r'$7.50'), // No decimal: parsed from the formatted amount.
    ])!;
    expect(totals.outflow, 20);
    expect(totals.inflow, 100);
    expect(totals.currency, 'USD');
    expect(totals.formatNet(locale: 'en_US'), r'+$80.00');
  });

  test('leaves out transfers, split parents and excluded rows', () {
    final totals = ActivityTotals.of([
      _row(decimal: '5'),
      _row(decimal: '50', splitParent: true),
      _row(decimal: '60', excluded: true),
      _row(decimal: '70', transfer: {'id': 't'}),
    ])!;
    expect(totals.outflow, 5);
    expect(totals.inflow, 0);
    expect(totals.formatNet(locale: 'en_US'), r'-$5.00');
  });

  test('mixed currencies have no total', () {
    expect(
      ActivityTotals.of(
          [_row(decimal: '1'), _row(decimal: '1', currency: 'EUR')]),
      isNull,
    );
  });

  test('nothing counted has no currency and a zero net', () {
    final totals = ActivityTotals.of(const [])!;
    expect(totals.currency, isNull);
    expect(totals.net, 0);
  });

  test('a sub-cent float remainder reads as zero', () {
    final totals = ActivityTotals.of([
      _row(decimal: '0.1'),
      _row(decimal: '0.2'),
      _row(decimal: '-0.3'),
    ])!;
    expect(totals.formatNet(locale: 'en_US'), r'$0.00');
  });
}
