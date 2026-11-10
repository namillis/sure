import '../models/recurring_transaction.dart';
import 'investment_math.dart';

/// Sections of the Recurring list, in display order.
enum RecurringGroup { upcoming, later, suggested, inactive }

/// Monthly totals of active recurring amounts in one currency, in major units.
class RecurringMonthlyTotal {
  const RecurringMonthlyTotal({this.outflow = 0, this.inflow = 0});

  final double outflow;
  final double inflow;
}

class RecurringGrouping {
  const RecurringGrouping._();

  /// Splits [items] into sections. Active items due on or before the end of
  /// [today]'s month (overdue included) are upcoming; other active items are
  /// later; suggestions from detection stand apart; paused, inactive and
  /// ended items are inactive. Each section is sorted by next expected date.
  static Map<RecurringGroup, List<RecurringTransaction>> group(
    List<RecurringTransaction> items,
    DateTime today,
  ) {
    final monthEnd = DateTime(today.year, today.month + 1, 0);
    final groups = {for (final g in RecurringGroup.values) g: <RecurringTransaction>[]};
    for (final item in items) {
      final RecurringGroup group;
      if (item.status == 'suggested') {
        group = RecurringGroup.suggested;
      } else if (!item.isActive) {
        group = RecurringGroup.inactive;
      } else {
        final next = item.nextExpectedDate;
        group = next != null && !next.isAfter(monthEnd)
            ? RecurringGroup.upcoming
            : RecurringGroup.later;
      }
      groups[group]!.add(item);
    }
    final far = DateTime(9999);
    for (final list in groups.values) {
      list.sort((a, b) =>
          (a.nextExpectedDate ?? far).compareTo(b.nextExpectedDate ?? far));
    }
    return groups;
  }

  /// The amount in major units, from `amount_cents` when present.
  static double amountOf(RecurringTransaction item) {
    final cents = item.amountCents;
    if (cents != null) {
      return InvestmentMath.fromMinorUnits(cents, currency: item.currency);
    }
    return InvestmentMath.parse(item.amount) ?? 0;
  }

  /// Per-currency monthly outflow and inflow of the active items, each
  /// scaled by how often it occurs in an average month.
  static Map<String, RecurringMonthlyTotal> monthlyTotals(
    List<RecurringTransaction> items,
  ) {
    final totals = <String, RecurringMonthlyTotal>{};
    for (final item in items.where((i) => i.isActive)) {
      final monthly = amountOf(item) * item.perMonth;
      final current = totals[item.currency] ?? const RecurringMonthlyTotal();
      totals[item.currency] = monthly < 0
          ? RecurringMonthlyTotal(
              outflow: current.outflow, inflow: current.inflow - monthly)
          : RecurringMonthlyTotal(
              outflow: current.outflow + monthly, inflow: current.inflow);
    }
    return totals;
  }
}
