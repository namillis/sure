import 'package:intl/intl.dart';

import 'amount_parser.dart';

/// The result of checking a set of split parts against the parent total.
class SplitCheck {
  const SplitCheck({
    required this.remainingUnits,
    required this.invalidRows,
    required this.rowCount,
  });

  /// Parent total minus the sum of the valid parts, in typed (parent-relative)
  /// direction, as ten-thousandths. Zero when the parts add up.
  final int remainingUnits;

  /// Indexes of rows whose amount is empty, unparseable, zero, or finer than
  /// [SplitMath.scale] decimals.
  final List<int> invalidRows;

  final int rowCount;

  bool get balanced => remainingUnits == 0;
  bool get hasEnoughRows => rowCount >= SplitMath.minRows;
  bool get isValid => hasEnoughRows && invalidRows.isEmpty && balanced;
}

/// Exact decimal arithmetic for split amounts.
///
/// The server stores amounts as decimal(19,4) and refuses a split whose
/// children don't sum to the parent exactly, so amounts are held as integer
/// ten-thousandths ("units") instead of doubles.
///
/// Parts are typed relative to the parent's direction: on an expense or an
/// income, a positive part goes the same way as the total and a negative part
/// goes the other way. [toServerUnits] maps them onto the API's convention
/// (positive = outflow, negative = inflow), which is the parent's
/// `amount_decimal` sign.
// shortcut: int is 64-bit on iOS/Android, which covers amounts below ~9.2e14;
// switch to BigInt if this ever has to run in a web build.
class SplitMath {
  const SplitMath._();

  static const int scale = 4;
  static const int minRows = 2;
  static const int _factor = 10000;
  static final RegExp _decimal = RegExp(r'^(-)?(\d{1,14})(?:\.(\d+))?$');

  /// Parses a canonical decimal string (`-12.5`, `30`, `0.0001`) into units,
  /// or null when it isn't one or has more than [scale] fraction digits.
  static int? toUnits(String? canonical) {
    if (canonical == null) return null;
    final match = _decimal.firstMatch(canonical.trim());
    if (match == null) return null;
    final fraction = (match.group(3) ?? '').replaceFirst(RegExp(r'0+$'), '');
    if (fraction.length > scale) return null;
    final units = int.parse(match.group(2)!) * _factor +
        int.parse(fraction.padRight(scale, '0'));
    return match.group(1) == null ? units : -units;
  }

  /// Units as a canonical decimal string with no trailing zeros (`12.5`).
  static String fromUnits(int units) {
    final negative = units < 0;
    final magnitude = units.abs();
    final whole = magnitude ~/ _factor;
    final fraction = (magnitude % _factor)
        .toString()
        .padLeft(scale, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    final text = fraction.isEmpty ? '$whole' : '$whole.$fraction';
    return negative ? '-$text' : text;
  }

  static double toDouble(int units) => units / _factor;

  /// Parses what the user typed into a part's amount field, or null when it
  /// is empty, not a number, or too precise.
  static int? parseTyped(String text, {String? locale}) {
    if (text.trim().isEmpty) return null;
    try {
      return toUnits(AmountParser.parse(text, locale: locale).canonicalValue);
    } on FormatException {
      return null;
    }
  }

  /// +1 for an outflow (or zero) parent, -1 for an inflow parent.
  static int direction(int parentServerUnits) => parentServerUnits < 0 ? -1 : 1;

  /// A typed part in the API's sign convention.
  static int toServerUnits(int typedUnits, {required int parentServerUnits}) =>
      typedUnits * direction(parentServerUnits);

  /// A child's stored amount as the user should see it typed.
  static int toTypedUnits(int serverUnits, {required int parentServerUnits}) =>
      serverUnits * direction(parentServerUnits);

  /// Checks [typedParts] (null for a row that didn't parse) against the
  /// parent's stored amount.
  static SplitCheck check({
    required int parentServerUnits,
    required List<int?> typedParts,
  }) {
    final invalid = <int>[];
    var sum = 0;
    for (var i = 0; i < typedParts.length; i++) {
      final part = typedParts[i];
      if (part == null || part == 0) {
        invalid.add(i);
      } else {
        sum += part;
      }
    }

    return SplitCheck(
      remainingUnits: parentServerUnits.abs() - sum,
      invalidRows: invalid,
      rowCount: typedParts.length,
    );
  }

  /// Text to prefill an amount field with: the value in the locale's decimal
  /// separator, at least [minFractionDigits] decimals, no grouping (so
  /// [AmountParser] reads it back unambiguously).
  static String toEditText(
    int units, {
    String? locale,
    int minFractionDigits = 2,
  }) {
    var text = fromUnits(units);
    final dot = text.indexOf('.');
    final digits = dot == -1 ? 0 : text.length - dot - 1;
    if (digits < minFractionDigits) {
      text = '${dot == -1 ? '$text.' : text}${'0' * (minFractionDigits - digits)}';
    }

    String separator;
    try {
      separator = NumberFormat.decimalPattern(locale).symbols.DECIMAL_SEP;
    } catch (_) {
      separator = '.';
    }
    return separator == '.' ? text : text.replaceFirst('.', separator);
  }
}
