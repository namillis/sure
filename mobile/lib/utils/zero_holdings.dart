import 'package:intl/intl.dart';

import '../models/account_holding.dart';
import 'investment_math.dart';

/// Holdings whose market value is zero (sold out, expired, worthless) are
/// hidden from holdings lists unless the user chooses to show them.
class ZeroHoldings {
  ZeroHoldings._();

  /// True when [holding]'s market value parses as exactly zero. An amount that
  /// does not parse is kept visible.
  static bool isZero(AccountHolding holding) =>
      InvestmentMath.parse(holding.amount) == 0;

  /// The holdings to list: all of them when [showZero], else the non-zero ones.
  static List<AccountHolding> visible(
    List<AccountHolding> holdings, {
    required bool showZero,
  }) =>
      showZero ? holdings : holdings.where((h) => !isZero(h)).toList();

  static int zeroCount(Iterable<AccountHolding> holdings) =>
      holdings.where(isZero).length;

  /// Zero in [currency] without decimals, e.g. `$0`.
  static String zeroLabel(String currency, {String? locale}) =>
      NumberFormat.simpleCurrency(
        locale: locale,
        name: currency,
        decimalDigits: 0,
      ).format(0);
}
