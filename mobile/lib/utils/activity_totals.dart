import 'package:intl/intl.dart';

import '../models/activity_transaction.dart';
import 'amount_parser.dart';

/// Money in and money out over a set of Activity rows, for the summary line
/// and the day headers.
///
/// The API's amounts are in the entry sign convention (positive = money out,
/// negative = money in). Transfers, split parents (their children carry the
/// amount) and excluded entries are left out, as in the server's reports.
///
/// shortcut: the API has no totals for a filter, so these are sums of the
/// rows the screen has loaded; switch to a server total if one is added.
class ActivityTotals {
  const ActivityTotals({
    required this.inflow,
    required this.outflow,
    required this.currency,
  });

  /// Money in, as a positive number.
  final double inflow;

  /// Money out, as a positive number.
  final double outflow;

  /// The rows' currency; null when nothing was counted.
  final String? currency;

  /// In minus out.
  double get net => inflow - outflow;

  /// The totals of [rows], or null when the counted rows mix currencies (a
  /// sum across them would be meaningless).
  static ActivityTotals? of(Iterable<ActivityTransaction> rows) {
    var inflow = 0.0;
    var outflow = 0.0;
    String? currency;
    for (final row in rows) {
      final t = row.transaction;
      if (row.isTransfer || row.isSplitParent || t.excluded == true) continue;
      final value = _value(t.amountDecimal, t.amount);
      if (value == null) continue;
      if (currency == null) {
        currency = t.currency;
      } else if (currency != t.currency) {
        return null;
      }
      if (value < 0) {
        inflow -= value;
      } else {
        outflow += value;
      }
    }
    return ActivityTotals(inflow: inflow, outflow: outflow, currency: currency);
  }

  static double? _value(String? decimal, String formatted) {
    final exact = decimal == null ? null : double.tryParse(decimal);
    if (exact != null) return exact;
    try {
      return AmountParser.parse(formatted).value;
    } on FormatException {
      return null;
    }
  }

  /// [value] in [currency] for [locale], e.g. `$1,926.88`.
  static String format(double value, String? currency, {String? locale}) {
    NumberFormat format;
    try {
      format = NumberFormat.simpleCurrency(locale: locale, name: currency);
    } catch (_) {
      format = NumberFormat.simpleCurrency(locale: locale);
    }
    return format.format(value);
  }

  /// [net] with a sign: `+$12.00`, `-$40.00`, or `$0.00`.
  String formatNet({String? locale}) {
    final text = format(net.abs(), currency, locale: locale);
    // Float sums can leave a sub-cent remainder; that reads as zero.
    if (net.abs() < 0.005) return format(0, currency, locale: locale);
    if (net > 0) return '+$text';
    if (net < 0) return '-$text';
    return text;
  }
}
