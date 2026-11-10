import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/models/activity_filters.dart';
import 'package:sure_mobile/models/activity_transaction.dart';
import 'package:sure_mobile/models/transaction.dart';
import 'package:sure_mobile/utils/transaction_amount_display.dart';
import 'package:sure_mobile/widgets/money_text.dart';

ActivityTransaction _row(String id, String date) => ActivityTransaction(
      transaction: Transaction(
        id: id,
        accountId: 'a',
        name: id,
        date: date,
        amount: r'$1.00',
        currency: 'USD',
        nature: 'expense',
      ),
    );

void main() {
  group('ActivityFilters.dateRange', () {
    ActivityDateRange range(ActivityDatePreset preset, DateTime now) =>
        ActivityFilters(datePreset: preset).dateRange(now);

    test('this month covers the whole calendar month', () {
      final r = range(ActivityDatePreset.thisMonth, DateTime(2026, 2, 14, 9));
      expect(r.start, DateTime(2026, 2, 1));
      expect(r.end, DateTime(2026, 2, 28));
    });

    test('last month in January is December of the year before', () {
      final r = range(ActivityDatePreset.lastMonth, DateTime(2026, 1, 5));
      expect(r.start, DateTime(2025, 12, 1));
      expect(r.end, DateTime(2025, 12, 31));
    });

    test('last 90 days is today and the 89 days before', () {
      final r = range(ActivityDatePreset.last90Days, DateTime(2026, 3, 31, 23));
      expect(r.end, DateTime(2026, 3, 31));
      expect(r.start, DateTime(2026, 1, 1));
    });

    test('this year and all time', () {
      final year = range(ActivityDatePreset.thisYear, DateTime(2026, 6, 1));
      expect(year.start, DateTime(2026, 1, 1));
      expect(year.end, DateTime(2026, 12, 31));
      final all = range(ActivityDatePreset.all, DateTime(2026, 6, 1));
      expect(all.start, isNull);
      expect(all.end, isNull);
    });
  });

  group('ActivityFilters', () {
    test('the default view has no active filters', () {
      expect(const ActivityFilters().hasActiveFilters, isFalse);
      expect(const ActivityFilters(search: '  ').hasActiveFilters, isFalse);
    });

    test('any search, other date or filter is active', () {
      const base = ActivityFilters();
      expect(base.copyWith(search: 'x').hasActiveFilters, isTrue);
      expect(
        base.copyWith(datePreset: ActivityDatePreset.all).hasActiveFilters,
        isTrue,
      );
      expect(base.copyWith(categoryIds: {'c'}).hasActiveFilters, isTrue);
      expect(base.copyWith(accountIds: {'a'}).hasActiveFilters, isTrue);
      expect(base.copyWith(tagIds: {'t'}).hasActiveFilters, isTrue);
      expect(
        base.copyWith(type: ActivityTypeFilter.income).hasActiveFilters,
        isTrue,
      );
    });

    test('copyWith can clear the type and keeps it when omitted', () {
      const income = ActivityFilters(type: ActivityTypeFilter.income);
      expect(income.copyWith(search: 'x').type, ActivityTypeFilter.income);
      expect(income.copyWith(type: null).type, isNull);
    });
  });

  group('ActivityTransaction.groupByDay', () {
    test('groups consecutive rows of the same date in order', () {
      final groups = ActivityTransaction.groupByDay([
        _row('a', '2026-11-10'),
        _row('b', '2026-11-10'),
        _row('c', '2026-11-08'),
        _row('d', 'not a date'),
      ]);
      expect(groups.map((g) => g.day), [
        DateTime(2026, 11, 10),
        DateTime(2026, 11, 8),
        null,
      ]);
      expect(groups.first.rows.map((r) => r.id), ['a', 'b']);
    });
  });

  group('TransactionAmountDisplay', () {
    test('an expense on an asset account is money out', () {
      final d = TransactionAmountDisplay.of(
        r'$12.50',
        isAsset: true,
        isLiability: false,
      );
      expect(d.text, r'-$12.50');
      expect(d.trend, MoneyTrend.outflow);
    });

    test('income on an asset account is money in', () {
      final d = TransactionAmountDisplay.of(
        r'-$40.00',
        isAsset: true,
        isLiability: false,
      );
      expect(d.text, r'$40.00');
      expect(d.trend, MoneyTrend.inflow);
    });

    test('an unparseable amount is neutral and shown as sent', () {
      final d = TransactionAmountDisplay.of(
        'n/a',
        isAsset: true,
        isLiability: false,
      );
      expect(d.text, 'n/a');
      expect(d.trend, MoneyTrend.neutral);
    });
  });
}
