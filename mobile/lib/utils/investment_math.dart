import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../models/account_holding.dart';
import 'amount_parser.dart';

/// Unrealized gain/loss for a position: market value minus cost basis.
class HoldingGain {
  const HoldingGain({required this.amount, required this.percent});

  final double amount;

  /// Fraction of cost basis (0.12 == 12%).
  final double percent;

  bool get isLoss => amount < 0;
}

/// Small numeric helpers for the investment screens. The API returns money as
/// already-formatted strings (`$1,234.56`), so values derived on the client
/// (gain/loss, range change) are parsed back here and re-formatted with the
/// account currency.
class InvestmentMath {
  const InvestmentMath._();

  /// Parses a formatted money or quantity string, or null when it has no
  /// digits.
  static double? parse(String? formatted) {
    if (formatted == null || formatted.trim().isEmpty) return null;
    try {
      return AmountParser.parse(formatted).value;
    } on FormatException {
      return null;
    }
  }

  /// Unrealized gain for [holding], or null when the provider sent no cost
  /// basis (or a zero one, which would make the percentage meaningless).
  static HoldingGain? gainFor(AccountHolding holding) {
    final quantity = parse(holding.quantity);
    final avgCost = parse(holding.avgCost);
    final marketValue = parse(holding.amount);
    if (quantity == null || avgCost == null || marketValue == null) {
      return null;
    }

    final costBasis = quantity * avgCost;
    if (costBasis == 0) return null;

    final gain = marketValue - costBasis;
    return HoldingGain(amount: gain, percent: gain / costBasis.abs());
  }

  /// Formats [value] in [currency]; with [signed], positives get a leading `+`.
  static String formatMoney(
    double value, {
    required String currency,
    String? locale,
    bool signed = false,
  }) {
    final formatted = _currencyFormat(currency, locale).format(value);
    return signed && value > 0 ? '+$formatted' : formatted;
  }

  /// Converts minor units (e.g. cents) for [currency] into a major-unit value.
  static double fromMinorUnits(int minor, {required String currency}) {
    final digits = _currencyFormat(currency, null).decimalDigits ?? 2;
    return minor / math.pow(10, digits);
  }

  /// Formats a fraction as a signed percentage, e.g. `+12.3%`.
  static String formatPercent(double fraction, {String? locale}) {
    final format = NumberFormat.decimalPercentPattern(
      locale: locale,
      decimalDigits: 1,
    );
    final formatted = format.format(fraction);
    return fraction > 0 ? '+$formatted' : formatted;
  }

  /// Trims a quantity like `12.500000` to `12.5` for display.
  static String formatQuantity(String quantity, {String? locale}) {
    final value = parse(quantity);
    if (value == null) return quantity;
    return NumberFormat.decimalPatternDigits(locale: locale, decimalDigits: 4)
        .format(value)
        .replaceFirstMapped(RegExp(r'([.,]\d*?)0+$'), (match) => match[1]!)
        .replaceFirst(RegExp(r'[.,]$'), '');
  }

  static NumberFormat _currencyFormat(String currency, String? locale) {
    try {
      return NumberFormat.simpleCurrency(locale: locale, name: currency);
    } catch (_) {
      return NumberFormat.simpleCurrency(locale: locale);
    }
  }
}
