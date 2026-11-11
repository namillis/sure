import '../models/account.dart';
import '../models/account_balance.dart';
import '../models/account_holding.dart';
import 'investment_math.dart';

/// One segment of the portfolio allocation bar. [label] is null for the
/// "everything else" bucket and for cash; [kind] tells them apart.
class AllocationSlice {
  const AllocationSlice({
    required this.kind,
    required this.value,
    required this.fraction,
    this.label,
  });

  final AllocationKind kind;
  final String? label;

  /// Market value in major units of the portfolio currency.
  final double value;

  /// Share of the whole bar, 0..1.
  final double fraction;
}

enum AllocationKind { holding, other, cash }

/// Aggregations for the portfolio screen. Every input is assumed to be in one
/// currency; the screen filters accounts by currency before calling these, so
/// amounts in different currencies are never added together.
class PortfolioMath {
  const PortfolioMath._();

  /// Positions shown individually in the allocation bar before the rest are
  /// grouped into one "other" slice.
  static const int allocationTopCount = 5;

  /// Sums several accounts' daily balance histories into one series, oldest
  /// first. Each account carries its last known balance forward across days
  /// it has no row for, and counts as zero before its first row.
  static List<AccountBalance> sumHistories(
    List<List<AccountBalance>> histories, {
    required String currency,
    String? locale,
  }) {
    final perAccount = <Map<DateTime, int>>[];
    final days = <DateTime>{};
    for (final history in histories) {
      final byDay = <DateTime, int>{};
      for (final balance in history) {
        final cents = balance.balanceCents;
        if (cents == null) continue;
        final day = _day(balance.date);
        byDay[day] = cents;
        days.add(day);
      }
      perAccount.add(byDay);
    }

    final sortedDays = days.toList()..sort();
    final carried = List<int>.filled(perAccount.length, 0);
    final summed = <AccountBalance>[];
    for (final day in sortedDays) {
      var total = 0;
      for (var i = 0; i < perAccount.length; i++) {
        final cents = perAccount[i][day];
        if (cents != null) carried[i] = cents;
        total += carried[i];
      }
      summed.add(AccountBalance(
        id: 'portfolio-${day.toIso8601String()}',
        date: day,
        currency: currency,
        balance: InvestmentMath.formatMoney(
          InvestmentMath.fromMinorUnits(total, currency: currency),
          currency: currency,
          locale: locale,
        ),
        balanceCents: total,
      ));
    }
    return summed;
  }

  /// Unrealized gain across every holding that has a cost basis; null when
  /// none does. Holdings without one are left out of both sides.
  static HoldingGain? totalGain(Iterable<AccountHolding> holdings) {
    var gain = 0.0;
    var costBasis = 0.0;
    var counted = 0;
    for (final holding in holdings) {
      final holdingGain = InvestmentMath.gainFor(holding);
      if (holdingGain == null) continue;
      gain += holdingGain.amount;
      costBasis += holdingGain.costBasis;
      counted += 1;
    }
    if (counted == 0 || costBasis == 0) return null;
    return HoldingGain(
      amount: gain,
      percent: gain / costBasis.abs(),
      costBasis: costBasis,
    );
  }

  /// Largest securities first (the same security held in several accounts is
  /// one slice), then one "other" slice for the rest, then cash. Zero and
  /// negative values are left out of the bar.
  static List<AllocationSlice> allocation(
    Iterable<AccountHolding> holdings, {
    double cash = 0,
  }) {
    final bySecurity = <String, ({String label, double value})>{};
    for (final holding in holdings) {
      final value = InvestmentMath.parse(holding.amount);
      if (value == null || value <= 0) continue;
      final ticker = holding.ticker?.trim();
      final name = holding.securityName?.trim();
      final label = ticker?.isNotEmpty == true ? ticker! : (name ?? '');
      final key = holding.securityId ?? label;
      final previous = bySecurity[key];
      bySecurity[key] = (label: label, value: (previous?.value ?? 0) + value);
    }
    final positions = bySecurity.values.toList()
      ..sort((left, right) => right.value.compareTo(left.value));

    final top = positions.take(allocationTopCount).toList();
    final otherValue = positions
        .skip(allocationTopCount)
        .fold<double>(0, (sum, position) => sum + position.value);
    final cashValue = cash > 0 ? cash : 0.0;
    final total = top.fold<double>(0, (sum, p) => sum + p.value) +
        otherValue +
        cashValue;
    if (total <= 0) return const [];

    return [
      for (final position in top)
        AllocationSlice(
          kind: AllocationKind.holding,
          label: position.label,
          value: position.value,
          fraction: position.value / total,
        ),
      if (otherValue > 0)
        AllocationSlice(
          kind: AllocationKind.other,
          value: otherValue,
          fraction: otherValue / total,
        ),
      if (cashValue > 0)
        AllocationSlice(
          kind: AllocationKind.cash,
          value: cashValue,
          fraction: cashValue / total,
        ),
    ];
  }

  /// Uninvested cash: the accounts' total balance minus their holdings'
  /// market value, never below zero.
  static double cash({
    required double accountsTotal,
    required Iterable<AccountHolding> holdings,
  }) {
    final invested = holdings.fold<double>(
      0,
      (sum, holding) => sum + (InvestmentMath.parse(holding.amount) ?? 0),
    );
    final cash = accountsTotal - invested;
    return cash > 0 ? cash : 0;
  }

  /// Change between the first and last balance of [series] (oldest first) in
  /// major units, plus that change as a fraction of the starting balance
  /// (null when it started at zero). Null with fewer than two balances.
  static ({double amount, double? percent})? change(
    List<AccountBalance> series,
  ) {
    final points =
        series.where((balance) => balance.balanceCents != null).toList();
    if (points.length < 2) return null;

    final currency = points.last.currency;
    final start = InvestmentMath.fromMinorUnits(
      points.first.balanceCents!,
      currency: currency,
    );
    final end = InvestmentMath.fromMinorUnits(
      points.last.balanceCents!,
      currency: currency,
    );
    return (
      amount: end - start,
      percent: start == 0 ? null : (end - start) / start.abs(),
    );
  }

  /// The currency the Invest tab opens in: [familyCurrency] when some account
  /// is in it, otherwise the currency with the largest total balance. Null
  /// for no accounts.
  static String? primaryCurrency(
    Iterable<Account> accounts, {
    String? familyCurrency,
  }) {
    final totals = <String, double>{};
    for (final account in accounts) {
      totals[account.currency] = (totals[account.currency] ?? 0) +
          (InvestmentMath.parse(account.balance) ?? 0);
    }
    if (totals.isEmpty) return null;
    if (familyCurrency != null && totals.containsKey(familyCurrency)) {
      return familyCurrency;
    }
    return totals.entries
        .reduce((best, entry) => entry.value > best.value ? entry : best)
        .key;
  }

  static DateTime _day(DateTime date) =>
      DateTime(date.year, date.month, date.day);
}
