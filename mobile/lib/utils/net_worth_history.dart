import '../models/account_balance.dart';

/// One account's input to [NetWorthHistory.build].
class NetWorthAccountHistory {
  const NetWorthAccountHistory({
    required this.accountId,
    required this.currency,
    required this.isLiability,
    this.currentCents,
    this.balances = const [],
  });

  final String accountId;
  final String currency;

  /// Liabilities are owed amounts (stored positive, like the balance sheet)
  /// and are subtracted.
  final bool isLiability;

  /// The account's current balance in minor units, from `/api/v1/accounts`.
  /// Used for accounts outside the main currency, and for a main-currency
  /// account that has no balance rows in the period.
  final int? currentCents;

  /// Daily balances (any order) on or after the period start.
  final List<AccountBalance> balances;
}

/// A day's net worth in minor units of the main currency.
class NetWorthPoint {
  const NetWorthPoint(this.date, this.cents);

  final DateTime date;
  final int cents;

  @override
  bool operator ==(Object other) =>
      other is NetWorthPoint && other.date == date && other.cents == cents;

  @override
  int get hashCode => Object.hash(date, cents);

  @override
  String toString() => 'NetWorthPoint($date, $cents)';
}

/// Net current balance of the accounts in one currency other than the main
/// one. These are never added to the main-currency line.
class NetWorthCurrencyTotal {
  const NetWorthCurrencyTotal({
    required this.currency,
    required this.cents,
    required this.accountCount,
  });

  final String currency;
  final int cents;
  final int accountCount;
}

/// Net worth over a period in the family's main currency, built on the phone
/// from each account's daily balances (the server has no net worth history
/// endpoint).
class NetWorthHistory {
  const NetWorthHistory({required this.points, required this.otherCurrencies});

  /// One point per day, oldest first. Empty when no main-currency account
  /// has any balance.
  final List<NetWorthPoint> points;

  /// Accounts in other currencies, one entry per currency, sorted by code.
  final List<NetWorthCurrencyTotal> otherCurrencies;

  int? get currentCents => points.isEmpty ? null : points.last.cents;

  /// Last minus first point; null with fewer than two points.
  int? get changeCents =>
      points.length < 2 ? null : points.last.cents - points.first.cents;

  /// Builds the series for [start]..[end] (date parts, inclusive).
  ///
  /// For each main-currency account, the last known balance carries forward
  /// over days without a row, and the first row in the period carries back to
  /// the period start. A late first row is almost always a gap in the synced
  /// history, not a new account; leaving those days at zero made the line
  /// jump on the day a big account's history began.
  /// An account with no rows at all contributes [currentCents] on every day.
  /// Balance rows in a currency other than their account's are ignored.
  static NetWorthHistory build({
    required List<NetWorthAccountHistory> accounts,
    required String mainCurrency,
    required DateTime start,
    required DateTime end,
  }) {
    final first = _day(start);
    final last = _day(end);

    final others = <String, NetWorthCurrencyTotal>{};
    final main = <NetWorthAccountHistory>[];
    for (final account in accounts) {
      if (account.currency == mainCurrency) {
        main.add(account);
        continue;
      }
      final sign = account.isLiability ? -1 : 1;
      final previous = others[account.currency];
      others[account.currency] = NetWorthCurrencyTotal(
        currency: account.currency,
        cents: (previous?.cents ?? 0) + sign * (account.currentCents ?? 0),
        accountCount: (previous?.accountCount ?? 0) + 1,
      );
    }
    final otherList = others.values.toList()
      ..sort((a, b) => a.currency.compareTo(b.currency));

    if (last.isBefore(first)) {
      return NetWorthHistory(points: const [], otherCurrencies: otherList);
    }

    // Per-day deltas: each account adds its balance on its first day and the
    // difference from its previous balance on each later row.
    final days = _dayCount(first, last);
    final deltas = List<int>.filled(days, 0);
    var anyData = false;
    for (final account in main) {
      final sign = account.isLiability ? -1 : 1;
      final rows = account.balances
          .where((b) => b.balanceCents != null && b.currency == account.currency)
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      if (rows.isEmpty) {
        final cents = account.currentCents;
        if (cents == null) continue;
        deltas[0] += sign * cents;
        anyData = true;
        continue;
      }
      int? previous;
      for (final row in rows) {
        final day = _day(row.date);
        if (day.isAfter(last)) break;
        // Rows before the start seed the opening balance, and so does the
        // first row inside the period (carried back to day one).
        final index = (previous == null || day.isBefore(first))
            ? 0
            : _dayCount(first, day) - 1;
        final value = sign * row.balanceCents!;
        deltas[index] += value - (previous ?? 0);
        previous = value;
        anyData = true;
      }
    }
    if (!anyData) {
      return NetWorthHistory(points: const [], otherCurrencies: otherList);
    }

    final points = <NetWorthPoint>[];
    var running = 0;
    for (var i = 0; i < days; i++) {
      running += deltas[i];
      points.add(
        NetWorthPoint(DateTime(first.year, first.month, first.day + i), running),
      );
    }
    return NetWorthHistory(points: points, otherCurrencies: otherList);
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Days in [a]..[b] inclusive. Uses UTC dates so DST never skews the count.
  static int _dayCount(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day)
          .difference(DateTime.utc(a.year, a.month, a.day))
          .inDays +
      1;
}
