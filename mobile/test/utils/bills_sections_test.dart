import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/models/recurring_transaction.dart';
import 'package:sure_mobile/utils/bills_sections.dart';

import '../support/recurring_fixtures.dart';

RecurringTransaction bill({
  String id = 'rt_1',
  String? next = '2026-11-20',
  String? last = '2026-10-20',
  String status = 'active',
  String billType = 'bill',
  int amountCents = 4999,
  String currency = 'USD',
}) =>
    RecurringTransaction.fromJson({
      ...recurringJson(
        id: id,
        status: status,
        amountCents: amountCents,
        currency: currency,
      ),
      'next_expected_date': next,
      'last_occurrence_date': last,
      'bill_type': billType,
    });

void main() {
  final today = DateTime(2026, 11, 10, 15, 30);
  BillsSection? classify(RecurringTransaction item, [DateTime? on]) =>
      BillsSections.classify(item, on ?? today);

  group('classify', () {
    test('overdue: next date passed with no later occurrence', () {
      expect(classify(bill(next: '2026-11-05', last: '2026-10-05')),
          BillsSection.overdue);
      expect(classify(bill(next: '2026-11-09', last: null)),
          BillsSection.overdue);
      expect(classify(bill(next: '2026-09-01', last: '2026-08-01')),
          BillsSection.overdue);
    });

    test('due this month runs from today through the month end', () {
      expect(classify(bill(next: '2026-11-10')), BillsSection.dueThisMonth);
      expect(classify(bill(next: '2026-11-30')), BillsSection.dueThisMonth);
      expect(classify(bill(next: '2026-12-01', last: '2026-10-01')),
          BillsSection.later);
    });

    test('paid this month: last occurrence in this month', () {
      expect(classify(bill(next: '2026-12-05', last: '2026-11-05')),
          BillsSection.paidThisMonth);
      expect(classify(bill(next: '2026-12-01', last: '2026-11-01')),
          BillsSection.paidThisMonth);
      // A stale next date already covered by this month's payment.
      expect(classify(bill(next: '2026-11-03', last: '2026-11-04')),
          BillsSection.paidThisMonth);
    });

    test('due beats paid when both apply', () {
      // Weekly: paid Nov 3, next Nov 17.
      expect(classify(bill(next: '2026-11-17', last: '2026-11-03')),
          BillsSection.dueThisMonth);
    });

    test('later: after this month, or no next date', () {
      expect(classify(bill(next: '2027-03-02', last: '2026-09-02')),
          BillsSection.later);
      expect(classify(bill(next: null, last: null)), BillsSection.later);
      expect(classify(bill(next: null, last: '2026-11-02')),
          BillsSection.paidThisMonth);
    });

    test('paused and inactive go to Paused whatever their dates', () {
      expect(classify(bill(status: 'paused', next: '2026-11-01')),
          BillsSection.paused);
      expect(classify(bill(status: 'inactive', next: '2026-11-20')),
          BillsSection.paused);
    });

    test('income, transfers, suggestions, ended and inflows are not bills',
        () {
      expect(classify(bill(billType: 'income')), isNull);
      expect(classify(bill(billType: 'transfer')), isNull);
      expect(classify(bill(status: 'suggested')), isNull);
      expect(classify(bill(status: 'ended')), isNull);
      expect(classify(bill(amountCents: -300000)), isNull);
      expect(classify(bill(billType: 'subscription')),
          BillsSection.dueThisMonth);
      expect(classify(bill(billType: 'installment')),
          BillsSection.dueThisMonth);
    });

    test('Jan 31 and February month ends', () {
      final jan31 = DateTime(2027, 1, 31);
      expect(classify(bill(next: '2027-01-31'), jan31),
          BillsSection.dueThisMonth);
      expect(classify(bill(next: '2027-02-01', last: '2026-12-01'), jan31),
          BillsSection.later);
      expect(classify(bill(next: '2027-01-30', last: '2026-12-30'), jan31),
          BillsSection.overdue);

      final feb28 = DateTime(2027, 2, 28);
      expect(classify(bill(next: '2027-02-28'), feb28),
          BillsSection.dueThisMonth);
      expect(classify(bill(next: '2027-03-01', last: '2027-02-01'), feb28),
          BillsSection.paidThisMonth);
      expect(classify(bill(next: '2027-03-01', last: '2027-01-31'), feb28),
          BillsSection.later);

      // Leap year: Feb 29 is still this month.
      expect(classify(bill(next: '2028-02-29'), DateTime(2028, 2, 10)),
          BillsSection.dueThisMonth);
    });
  });

  test('group puts each bill in one section, sorted by date', () {
    final groups = BillsSections.group([
      bill(id: 'late', next: '2026-11-08', last: '2026-10-08'),
      bill(id: 'later_late', next: '2026-10-01', last: '2026-09-01'),
      bill(id: 'due2', next: '2026-11-25'),
      bill(id: 'due1', next: '2026-11-12'),
      bill(id: 'paid', next: '2026-12-03', last: '2026-11-03'),
      bill(id: 'march', next: '2027-03-02', last: '2026-09-02'),
      bill(id: 'dec', next: '2026-12-20', last: '2026-10-20'),
      bill(id: 'paused', status: 'inactive'),
      bill(id: 'salary', billType: 'income'),
    ], today);

    List<String> ids(BillsSection s) => groups[s]!.map((i) => i.id).toList();
    expect(ids(BillsSection.overdue), ['later_late', 'late']);
    expect(ids(BillsSection.dueThisMonth), ['due1', 'due2']);
    expect(ids(BillsSection.paidThisMonth), ['paid']);
    expect(ids(BillsSection.later), ['dec', 'march']);
    expect(ids(BillsSection.paused), ['paused']);
    final total = groups.values.fold<int>(0, (sum, l) => sum + l.length);
    expect(total, 8);
  });

  group('summary', () {
    test('sums overdue + due as left to pay and paid separately', () {
      final groups = BillsSections.group([
        bill(id: 'late', next: '2026-11-08', last: '2026-10-08',
            amountCents: 10000),
        bill(id: 'due', next: '2026-11-25', amountCents: 2500),
        bill(id: 'paid', next: '2026-12-03', last: '2026-11-03',
            amountCents: 5000),
        bill(id: 'later', next: '2027-01-03', last: '2026-10-03',
            amountCents: 99900),
      ], today);
      final summary = BillsSections.summary(groups, 'USD');
      expect(summary.leftToPay, 125.0);
      expect(summary.paid, 50.0);
      expect(summary.total, 175.0);
      expect(summary.paidCount, 1);
      expect(summary.billCount, 3);
      expect(summary.otherCurrencyCount, 0);
      expect(summary.paidFraction, closeTo(50 / 175, 1e-9));
    });

    test('leaves other currencies out of the amounts but counts them', () {
      final groups = BillsSections.group([
        bill(id: 'due', next: '2026-11-25', amountCents: 2500),
        bill(id: 'eur', next: '2026-11-26', amountCents: 9900,
            currency: 'EUR'),
        bill(id: 'eur_paid', next: '2026-12-01', last: '2026-11-01',
            amountCents: 1000, currency: 'EUR'),
      ], today);
      final summary = BillsSections.summary(groups, 'USD');
      expect(summary.leftToPay, 25.0);
      expect(summary.paid, 0);
      expect(summary.billCount, 3);
      expect(summary.paidCount, 1);
      expect(summary.otherCurrencyCount, 2);
    });

    test('nothing owed gives a zero fraction', () {
      final summary = BillsSections.summary(
          BillsSections.group(const [], today), 'USD');
      expect(summary.total, 0);
      expect(summary.paidFraction, 0);
    });
  });

  test('mainCurrency prefers the family currency, else the most common', () {
    final items = [
      bill(currency: 'EUR'),
      bill(id: 'b', currency: 'EUR'),
      bill(id: 'c', currency: 'USD'),
    ];
    expect(BillsSections.mainCurrency(items, 'SEK'), 'SEK');
    expect(BillsSections.mainCurrency(items, null), 'EUR');
    expect(BillsSections.mainCurrency(const [], ''), 'USD');
  });

  test('parses renews_on and trial_ends_on', () {
    final item = RecurringTransaction.fromJson({
      ...recurringJson(),
      'renews_on': '2027-01-15',
      'trial_ends_on': '2026-11-20',
    });
    expect(item.renewsOn, DateTime(2027, 1, 15));
    expect(item.trialEndsOn, DateTime(2026, 11, 20));
    expect(RecurringTransaction.fromJson(recurringJson()).renewsOn, isNull);
  });
}
