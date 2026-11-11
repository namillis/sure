import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/privacy_provider.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../utils/investment_math.dart';
import '../utils/money_masker.dart';
import '../utils/net_worth_history.dart';
import 'balance_history_chart.dart' show AccountChartRange;
import 'money_text.dart';
import 'sure_chip.dart';

/// Home's net worth hero, on the page background: the "Net worth" label, the
/// server's balance-sheet net worth as the hero amount, the change over the
/// selected [range] (from [history]), a small trend line and the
/// 1M / 3M / 1Y / All range chips.
class NetWorthCard extends StatelessWidget {
  const NetWorthCard({
    super.key,
    this.netWorthFormatted,
    this.isStale = false,
    this.updatedLabel,
    this.history,
    this.historyCurrency,
    this.historyLoading = false,
    this.range = AccountChartRange.quarter,
    this.onRangeChanged,
  });

  /// Ranges the chips offer, in order.
  static const ranges = [
    AccountChartRange.month,
    AccountChartRange.quarter,
    AccountChartRange.year,
    AccountChartRange.all,
  ];

  static const double chartHeight = 56;

  /// The balance sheet's formatted net worth; "--" when unknown.
  final String? netWorthFormatted;

  /// The balance sheet could not be refreshed: dims the amount and shows an
  /// "Outdated" badge.
  final bool isStale;

  /// Small hint under the net worth, e.g. "Updated 5 minutes ago", shown
  /// while the figures come from the offline cache.
  final String? updatedLabel;

  /// Net worth over [range] in [historyCurrency]. Null hides the change line
  /// and the trend line.
  final NetWorthHistory? history;
  final String? historyCurrency;

  /// Keeps the trend line's space while [history] loads, so the chips do not
  /// jump.
  final bool historyLoading;
  final AccountChartRange range;

  /// Null hides the range chips.
  final ValueChanged<AccountChartRange>? onRangeChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final hidden = context.watch<PrivacyProvider>().hidden;
    final locale = Localizations.localeOf(context).toString();
    final netWorth = netWorthFormatted == null
        ? '--'
        : MoneyMasker.mask(netWorthFormatted!, hidden: hidden);

    final history = this.history;
    final currency = historyCurrency;
    final change = history?.changeCents;
    final showChart = history != null && history.points.length >= 2;
    final rising = (change ?? 0) >= 0;
    final trendColor = rising ? palette.success : palette.destructive;

    String? changeText;
    if (change != null && currency != null && currency.isNotEmpty) {
      final amount = InvestmentMath.formatMoney(
        InvestmentMath.fromMinorUnits(change, currency: currency),
        currency: currency,
        locale: locale,
        signed: true,
      );
      final first = history!.points.first.cents;
      final percent = first == 0
          ? null
          : NumberFormat.decimalPercentPattern(locale: locale, decimalDigits: 1)
              .format((change / first).abs());
      changeText = MoneyMasker.mask(
        percent == null ? amount : '$amount ($percent)',
        hidden: hidden,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  l.p3rpNetWorth,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: palette.textSecondary),
                ),
              ),
              if (isStale) ...[
                const SizedBox(width: 6),
                Container(
                  key: const ValueKey('netWorthOutdated'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: palette.surfaceInset,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    l.dshOutdated,
                    style: TextStyle(
                      fontSize: 11,
                      color: palette.textSubdued,
                      fontWeight: SureTokens.weightMedium,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: MoneyText(
              netWorth,
              key: const ValueKey('netWorthHero'),
              trend: MoneyTrend.neutral,
              color: isStale ? palette.textSubdued : palette.textPrimary,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 32,
                height: 1.2,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
              ),
            ),
          ),
          if (changeText != null)
            Text.rich(
              key: const ValueKey('netWorthChange'),
              TextSpan(children: [
                TextSpan(
                  text: changeText,
                  style: SureMoney.tabular(
                    TextStyle(
                      color: trendColor,
                      fontWeight: SureTokens.weightMedium,
                    ),
                  ),
                ),
                TextSpan(
                  text: '  ${range.label(l)}',
                  style: TextStyle(color: palette.textSubdued),
                ),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          if (updatedLabel != null)
            Text(
              updatedLabel!,
              key: const ValueKey('netWorthUpdatedLabel'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: palette.textSubdued),
            ),
          if (showChart || historyLoading) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: chartHeight,
              width: double.infinity,
              child: showChart
                  ? Semantics(
                      label: l.p3rpNetWorthChartLabel,
                      child: CustomPaint(
                        key: const ValueKey('netWorthSparkline'),
                        painter: _SparklinePainter(
                          values: [for (final p in history.points) p.cents],
                          color: trendColor,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
          if (onRangeChanged != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final r in ranges)
                  SureChip(
                    label: r.label(l),
                    selected: r == range,
                    onSelected: (_) {
                      if (r != range) onRangeChanged!(r);
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A 1.5 px line through [values] (no axes) with a very faint fill under it.
class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required List<int> values, required this.color})
      : values = _sample(values, 240);

  final List<int> values;
  final Color color;

  static List<int> _sample(List<int> values, int max) {
    if (values.length <= max) return values;
    final step = (values.length - 1) / (max - 1);
    return [for (var i = 0; i < max; i++) values[(i * step).round()]];
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var lo = values.first, hi = values.first;
    for (final v in values) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final span = (hi - lo).toDouble();
    const inset = 2.0;
    final h = size.height - inset * 2;
    double y(int v) =>
        inset + (span == 0 ? h / 2 : h - (v - lo) / span * h);
    final dx = size.width / (values.length - 1);

    final line = Path()..moveTo(0, y(values.first));
    for (var i = 1; i < values.length; i++) {
      line.lineTo(i * dx, y(values[i]));
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.10), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.color != color || !_sameValues(old.values, values);

  static bool _sameValues(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
