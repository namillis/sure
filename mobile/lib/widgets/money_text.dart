import 'package:flutter/material.dart';

import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';

/// Directional meaning of a monetary value, used to pick its semantic color.
/// This mirrors the app's existing in/out coloring (money in is positive, money
/// out is negative) but routes it through Sure design-system tokens instead of
/// raw [Colors.green]/[Colors.red].
enum MoneyTrend {
  /// Money coming in (positive change, income, a gain). Uses `success`.
  inflow,

  /// Money going out (negative change, expense, a loss). Uses `destructive`.
  outflow,

  /// No directional meaning / unknown amount. Uses `textSubdued`.
  neutral,
}

/// Shared money typography + semantic color, so every screen renders monetary
/// values the same way: tabular figures (digits stay aligned across rows) and a
/// design-system color chosen from the value's [MoneyTrend].
///
/// Convention for callers:
/// - Directionally-colored amounts (income/expense, +/- changes): use
///   [MoneyText] (or [style]) with a [MoneyTrend] — it applies the semantic
///   color *and* tabular figures, so do not also wrap the style in [tabular].
/// - Neutral amounts that are not directionally colored (account balances, net
///   worth, per-currency totals): use [tabular] to keep digits aligned without
///   changing the color. [MoneyTrend.neutral] is reserved for unknown/unparsed
///   amounts (renders in `textSubdued`).
class SureMoney {
  const SureMoney._();

  /// The design-system color for [trend] in the active theme.
  static Color color(BuildContext context, MoneyTrend trend) {
    final palette = SureColors.of(context).palette;
    switch (trend) {
      case MoneyTrend.inflow:
        return palette.success;
      case MoneyTrend.outflow:
        return palette.destructive;
      case MoneyTrend.neutral:
        return palette.textSubdued;
    }
  }

  /// Derive a [MoneyTrend] from a signed amount. `null` amounts are [neutral].
  static MoneyTrend trendForAmount(double? amount) {
    if (amount == null) {
      return MoneyTrend.neutral;
    }
    return amount >= 0 ? MoneyTrend.inflow : MoneyTrend.outflow;
  }

  /// A money [TextStyle]: [base] (so callers keep their size) plus the semantic
  /// color for [trend], Geist Mono and tabular figures for column-aligned
  /// digits.
  static TextStyle style(
    BuildContext context, {
    required MoneyTrend trend,
    TextStyle? base,
  }) {
    final resolved = tabular(base);
    return resolved.copyWith(
      color: color(context, trend),
      fontWeight: resolved.fontWeight ?? FontWeight.w600,
    );
  }

  /// Apply only money typography (Geist Mono with tabular figures) to [base],
  /// leaving the color untouched. For neutral balances/totals (e.g. net
  /// worth) that are not directionally colored but should still keep digits
  /// column-aligned.
  static TextStyle tabular(TextStyle? base) {
    return (base ?? const TextStyle()).copyWith(
      fontFamily: SureTokens.fontMono,
      fontFamilyFallback: const <String>['Menlo', 'monospace'],
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
  }
}

/// Renders a pre-formatted monetary [text] in Geist Mono with tabular figures
/// and the semantic color for [trend] (or an explicit [color]).
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.text, {
    super.key,
    required this.trend,
    this.style,
    this.textAlign,
    this.overflow,
    this.color,
    this.maxLines,
  });

  final String text;
  final MoneyTrend trend;

  /// Base style (size/weight). Font, color and tabular figures are applied on
  /// top.
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextOverflow? overflow;

  /// Overrides the [trend] color, for amounts whose color is not their
  /// direction (e.g. expenses in `textPrimary`, transfers in `textSecondary`).
  final Color? color;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final resolved = SureMoney.style(context, trend: trend, base: style);
    return Text(
      text,
      textAlign: textAlign,
      overflow: overflow,
      maxLines: maxLines,
      softWrap: maxLines == 1 ? false : null,
      style: color == null ? resolved : resolved.copyWith(color: color),
    );
  }
}

