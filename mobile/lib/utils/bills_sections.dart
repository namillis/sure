import '../models/recurring_transaction.dart';
import 'recurring_grouping.dart';

/// Sections of the Bills view, in display order.
enum BillsSection { overdue, dueThisMonth, paidThisMonth, later, paused }

/// The month's bill totals in the family's main currency, in major units.
class BillsSummary {
  const BillsSummary({
    required this.leftToPay,
    required this.paid,
    required this.paidCount,
    required this.billCount,
    required this.otherCurrencyCount,
  });

  /// Overdue plus due this month.
  final double leftToPay;
  final double paid;

  /// Bills paid this month, in any currency.
  final int paidCount;

  /// Paid, overdue and due this month, in any currency.
  final int billCount;

  /// Bills in those three sections left out of the amounts because they are
  /// in another currency.
  final int otherCurrencyCount;

  double get total => leftToPay + paid;

  /// Share of the month's bills already paid, 0..1 (0 with nothing owed).
  double get paidFraction => total <= 0 ? 0 : paid / total;
}

/// Mirrors the web Bills overview (`BillsController#index`) from series data
/// only: the API has no occurrence rows, so "paid" means the series' last
/// occurrence fell in this month and "overdue" means its next expected date
/// passed without a later occurrence.
class BillsSections {
  const BillsSections._();

  /// Whether [item] is a bill at all, as the web's `payable_series_ids`:
  /// money out, not income or a transfer, and not a suggestion or ended.
  static bool isBill(RecurringTransaction item) {
    const statuses = {'active', 'inactive', 'paused'};
    if (!statuses.contains(item.status)) return false;
    if (item.billType == 'income' || item.billType == 'transfer') return false;
    return RecurringGrouping.amountOf(item) > 0;
  }

  /// The one section [item] belongs in on [today] (a local calendar day), or
  /// null when it is not a bill.
  static BillsSection? classify(RecurringTransaction item, DateTime today) {
    if (!isBill(item)) return null;
    if (!item.isActive) return BillsSection.paused;

    final day = _day(today);
    final monthStart = DateTime(day.year, day.month);
    final monthEnd = DateTime(day.year, day.month + 1, 0);
    final next = _dayOrNull(item.nextExpectedDate);
    final last = _dayOrNull(item.lastOccurrenceDate);

    if (next != null && next.isBefore(day) && (last == null || last.isBefore(next))) {
      return BillsSection.overdue;
    }
    if (next != null && !next.isBefore(day) && !next.isAfter(monthEnd)) {
      return BillsSection.dueThisMonth;
    }
    if (last != null && !last.isBefore(monthStart) && !last.isAfter(monthEnd)) {
      return BillsSection.paidThisMonth;
    }
    // Next date after this month, plus the odd active bill with no next date
    // or a stale one already paid, so every active bill shows somewhere.
    return BillsSection.later;
  }

  /// Bills of [items] split by section. Overdue and Paused sort oldest
  /// first, Due and Later by next date, Paid by last payment; missing dates
  /// sort last.
  static Map<BillsSection, List<RecurringTransaction>> group(
    List<RecurringTransaction> items,
    DateTime today,
  ) {
    final sections = {
      for (final s in BillsSection.values) s: <RecurringTransaction>[],
    };
    for (final item in items) {
      final section = classify(item, today);
      if (section != null) sections[section]!.add(item);
    }
    final far = DateTime(9999);
    int byNext(RecurringTransaction a, RecurringTransaction b) =>
        (a.nextExpectedDate ?? far).compareTo(b.nextExpectedDate ?? far);
    for (final entry in sections.entries) {
      if (entry.key == BillsSection.paidThisMonth) {
        entry.value.sort((a, b) => (a.lastOccurrenceDate ?? far)
            .compareTo(b.lastOccurrenceDate ?? far));
      } else {
        entry.value.sort(byNext);
      }
    }
    return sections;
  }

  /// Totals of [sections] in [currency]; bills in other currencies are
  /// counted but left out of the amounts.
  static BillsSummary summary(
    Map<BillsSection, List<RecurringTransaction>> sections,
    String currency,
  ) {
    var left = 0.0;
    var paid = 0.0;
    var other = 0;
    void add(List<RecurringTransaction> items, bool isPaid) {
      for (final item in items) {
        if (item.currency != currency) {
          other++;
          continue;
        }
        final amount = RecurringGrouping.amountOf(item);
        if (isPaid) {
          paid += amount;
        } else {
          left += amount;
        }
      }
    }

    final overdue = sections[BillsSection.overdue] ?? const [];
    final due = sections[BillsSection.dueThisMonth] ?? const [];
    final paidItems = sections[BillsSection.paidThisMonth] ?? const [];
    add(overdue, false);
    add(due, false);
    add(paidItems, true);
    return BillsSummary(
      leftToPay: left,
      paid: paid,
      paidCount: paidItems.length,
      billCount: overdue.length + due.length + paidItems.length,
      otherCurrencyCount: other,
    );
  }

  /// The currency totals are shown in: [familyCurrency] when known, else the
  /// most common currency among [items] (USD with none).
  static String mainCurrency(
    List<RecurringTransaction> items,
    String? familyCurrency,
  ) {
    if (familyCurrency != null && familyCurrency.isNotEmpty) {
      return familyCurrency;
    }
    final counts = <String, int>{};
    for (final item in items) {
      counts[item.currency] = (counts[item.currency] ?? 0) + 1;
    }
    if (counts.isEmpty) return 'USD';
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime? _dayOrNull(DateTime? d) => d == null ? null : _day(d);
}
