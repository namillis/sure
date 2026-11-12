import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/models/recurring_transaction.dart';
import 'package:sure_mobile/models/transaction.dart';
import 'package:sure_mobile/screens/transaction_edit_screen.dart';

import '../support/recurring_fixtures.dart';

Transaction _txn({
  String name = 'Netflix.com 1234',
  String amountDecimal = '15.49',
  String classification = 'expense',
  String date = '2026-01-31',
  Map<String, dynamic>? merchant = const {'id': 'm_netflix', 'name': 'Netflix'},
  String currency = 'USD',
  String? kind,
  bool? excluded,
  Map<String, dynamic>? transfer,
}) =>
    Transaction.fromJson({
      'id': 'txn_1',
      'entry_id': 'entry_1',
      'date': date,
      'amount': '\$$amountDecimal',
      'amount_decimal': amountDecimal,
      'currency': currency,
      'name': name,
      'classification': classification,
      'account': {'id': 'acct_1', 'name': 'Checking'},
      'merchant': merchant,
      if (kind != null) 'kind': kind,
      if (excluded != null) 'excluded': excluded,
      'transfer': transfer,
    });

RecurringTransaction _item({
  String id = 'rt_1',
  String? name = 'Netflix',
  int amountCents = 1549,
  String status = 'active',
  String currency = 'USD',
  Map<String, dynamic>? merchant = const {'id': 'm_netflix', 'name': 'Netflix'},
  int? minCents,
  int? maxCents,
}) =>
    RecurringTransaction.fromJson({
      ...recurringJson(
        id: id,
        name: name,
        amount: '\$${(amountCents / 100).toStringAsFixed(2)}',
        amountCents: amountCents,
        status: status,
        currency: currency,
        merchant: merchant,
      ),
      'expected_amount_min_cents': minCents,
      'expected_amount_max_cents': maxCents,
    });

void main() {
  final l = lookupAppLocalizations(const Locale('en'));

  group('Transaction.fromJson', () {
    test('parses transfer, kind and excluded', () {
      final t = _txn(
        kind: 'funds_movement',
        excluded: true,
        transfer: {
          'id': 'tr_1',
          'amount': '\$15.49',
          'currency': 'USD',
          'other_account': {
            'id': 'acct_2',
            'name': 'Savings',
            'account_type': 'depository',
          },
        },
      );
      expect(t.kind, 'funds_movement');
      expect(t.excluded, isTrue);
      expect(t.transfer!.id, 'tr_1');
      expect(t.transfer!.amount, '\$15.49');
      expect(t.transfer!.currency, 'USD');
      expect(t.transfer!.otherAccountId, 'acct_2');
      expect(t.transfer!.otherAccountName, 'Savings');
      expect(t.transfer!.otherAccountType, 'depository');
    });

    test('no transfer, kind or excluded when absent or null', () {
      final t = _txn();
      expect(t.transfer, isNull);
      expect(t.kind, isNull);
      expect(t.excluded, isNull);
    });

    test('a transfer without other_account keeps the id only', () {
      final t = _txn(transfer: {'id': 'tr_1'});
      expect(t.transfer!.id, 'tr_1');
      expect(t.transfer!.otherAccountName, isNull);
    });
  });

  test('RecurringTransaction parses merchant id and the expected range', () {
    final item = _item(minCents: 1400, maxCents: 1700);
    expect(item.merchantId, 'm_netflix');
    expect(item.expectedAmountMinCents, 1400);
    expect(item.expectedAmountMaxCents, 1700);
    expect(_item(merchant: null).merchantId, isNull);
  });

  group('transferLabel', () {
    const transfer =
        TransactionTransfer(id: 'tr_1', otherAccountName: 'Savings');
    test('outflow reads "To"', () {
      expect(transferLabel(l, _txn(), transfer), 'To Savings');
    });
    test('inflow reads "From"', () {
      expect(
        transferLabel(
          l,
          _txn(amountDecimal: '-15.49', classification: 'income'),
          transfer,
        ),
        'From Savings',
      );
    });
    test('falls back when the other account is unknown', () {
      expect(
        transferLabel(l, _txn(), const TransactionTransfer(id: 'tr_1')),
        'To another account',
      );
    });
  });

  group('budgetsAndReportsLabel', () {
    final cases = <(String?, bool?), String>{
      (null, null): 'Included',
      ('standard', false): 'Included',
      ('something_new', false): 'Included',
      ('one_time', false): 'One-time',
      ('funds_movement', false): 'Transfer, not counted',
      ('cc_payment', false): 'Card payment, not counted',
      ('loan_payment', false): 'Counted as expense',
      ('investment_contribution', false): 'Counted as expense',
      ('standard', true): 'Excluded',
      ('one_time', true): 'Excluded',
    };
    cases.forEach((input, expected) {
      test('$input -> $expected', () {
        expect(
          budgetsAndReportsLabel(l, _txn(kind: input.$1, excluded: input.$2)),
          expected,
        );
      });
    });
  });

  group('findRecurringMatch', () {
    test('matches on merchant id and amount within 10%', () {
      final item = _item(
          amountCents: 1500,
          merchant: {'id': 'm_netflix', 'name': 'Other name'});
      expect(findRecurringMatch(_txn(), [item]), same(item));
    });

    test('a different merchant id does not match', () {
      final item = _item(merchant: {'id': 'm_other', 'name': 'Netflix'});
      expect(findRecurringMatch(_txn(), [item]), isNull);
    });

    test('falls back to the merchant name, case-insensitively', () {
      final item = _item(merchant: null, name: 'NETFLIX ');
      // The item carries no merchant at all, so its merchant name is null and
      // the merchant-name rule cannot match it.
      expect(findRecurringMatch(_txn(), [item]), isNull);

      const named = RecurringTransaction(
        id: 'rt_2',
        amount: '\$15.49',
        amountCents: 1549,
        currency: 'USD',
        status: 'active',
        merchantName: 'netflix',
      );
      expect(findRecurringMatch(_txn(), [named]), same(named));
    });

    test('without a merchant, matches the normalized name', () {
      final item =
          _item(name: 'gym   membership', merchant: null, amountCents: 4999);
      final t =
          _txn(name: ' Gym Membership', merchant: null, amountDecimal: '49.99');
      expect(findRecurringMatch(t, [item]), same(item));
      expect(
        findRecurringMatch(
            _txn(name: 'Gym', merchant: null, amountDecimal: '49.99'), [item]),
        isNull,
      );
    });

    test('uses the expected min..max when the item has one', () {
      final item = _item(amountCents: 1000, minCents: 1400, maxCents: 2000);
      expect(
          findRecurringMatch(_txn(amountDecimal: '19.99'), [item]), same(item));
      expect(findRecurringMatch(_txn(amountDecimal: '20.01'), [item]), isNull);
      expect(findRecurringMatch(_txn(amountDecimal: '13.99'), [item]), isNull);
    });

    test('without a range, allows 10% either way', () {
      final item = _item(amountCents: 1000);
      expect(
          findRecurringMatch(_txn(amountDecimal: '11.00'), [item]), same(item));
      expect(
          findRecurringMatch(_txn(amountDecimal: '9.00'), [item]), same(item));
      expect(findRecurringMatch(_txn(amountDecimal: '11.01'), [item]), isNull);
    });

    test('compares inflows by size too', () {
      final item = _item(amountCents: -1549);
      expect(
        findRecurringMatch(
          _txn(amountDecimal: '-15.49', classification: 'income'),
          [item],
        ),
        same(item),
      );
    });

    test('skips ended items and other currencies', () {
      expect(findRecurringMatch(_txn(), [_item(status: 'ended')]), isNull);
      expect(findRecurringMatch(_txn(), [_item(currency: 'EUR')]), isNull);
    });

    test('prefers an active item over an inactive one', () {
      final paused = _item(id: 'rt_paused', status: 'paused');
      final active = _item(id: 'rt_active');
      expect(findRecurringMatch(_txn(), [paused, active]), same(active));
      expect(findRecurringMatch(_txn(), [paused]), same(paused));
    });
  });

  group('addOneMonthClamped', () {
    test('clamps the day to the next month', () {
      expect(addOneMonthClamped(DateTime(2026, 1, 31)), DateTime(2026, 2, 28));
      expect(addOneMonthClamped(DateTime(2028, 1, 31)), DateTime(2028, 2, 29));
      expect(addOneMonthClamped(DateTime(2026, 3, 31)), DateTime(2026, 4, 30));
      expect(addOneMonthClamped(DateTime(2026, 12, 15)), DateTime(2027, 1, 15));
    });
  });

  group('recurringPrefillFor', () {
    test('fills from the transaction, merchant name first', () {
      final p = recurringPrefillFor(_txn());
      expect(p.name, 'Netflix');
      expect(p.amount, 15.49);
      expect(p.income, isFalse);
      expect(p.currency, 'USD');
      expect(p.accountId, 'acct_1');
      expect(p.merchantId, 'm_netflix');
      expect(p.expectedDayOfMonth, 31);
      expect(p.lastOccurrenceDate, DateTime(2026, 1, 31));
      expect(p.nextExpectedDate, DateTime(2026, 2, 28));
    });

    test('uses the transaction name without a merchant; income stays income',
        () {
      final p = recurringPrefillFor(_txn(
        name: 'Salary',
        merchant: null,
        amountDecimal: '-2500',
        classification: 'income',
        date: '2028-01-31',
      ));
      expect(p.name, 'Salary');
      expect(p.amount, 2500);
      expect(p.income, isTrue);
      expect(p.merchantId, isNull);
      expect(p.nextExpectedDate, DateTime(2028, 2, 29));
    });
  });
}
