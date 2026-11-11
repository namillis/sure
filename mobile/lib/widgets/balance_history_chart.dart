import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/account_balance.dart';
import '../theme/sure_colors.dart';

/// Time windows offered above the balance chart.
enum AccountChartRange {
  week(7),
  month(30),
  quarter(90),
  year(365),
  all(null);

  const AccountChartRange(this.days);

  /// Length of the window in days; null means the account's full history.
  final int? days;

  DateTime? startDate(DateTime now) {
    final days = this.days;
    if (days == null) return null;
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: days));
  }

  /// Short chip label, e.g. `1M`.
  String label(AppLocalizations l) => switch (this) {
        AccountChartRange.week => l.accountRangeWeek,
        AccountChartRange.month => l.accountRangeMonth,
        AccountChartRange.quarter => l.accountRangeQuarter,
        AccountChartRange.year => l.accountRangeYear,
        AccountChartRange.all => l.accountRangeAll,
      };
}

/// Line chart of an account's balance over time: a [color] line over a faint
/// gradient fill, no axes. Press and drag to inspect a point (a thin vertical
/// guide and a dot); [onSelectionChanged] reports the touched balance (null on release)
/// so the surrounding header can show its value and date.
class BalanceHistoryChart extends StatefulWidget {
  const BalanceHistoryChart({
    super.key,
    required this.balances,
    required this.color,
    this.onSelectionChanged,
    this.semanticLabel,
  });

  /// Balances ordered oldest first. Entries without minor units are skipped.
  final List<AccountBalance> balances;
  final Color color;
  final ValueChanged<AccountBalance?>? onSelectionChanged;
  final String? semanticLabel;

  /// Max points painted; longer histories are evenly sampled.
  static const int maxPoints = 240;

  @override
  State<BalanceHistoryChart> createState() => _BalanceHistoryChartState();
}

class _BalanceHistoryChartState extends State<BalanceHistoryChart> {
  late List<AccountBalance> _points = _sample(widget.balances);
  int? _selectedIndex;

  @override
  void didUpdateWidget(covariant BalanceHistoryChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.balances, widget.balances)) {
      _points = _sample(widget.balances);
      _selectedIndex = null;
    }
  }

  static List<AccountBalance> _sample(List<AccountBalance> balances) {
    final usable =
        balances.where((balance) => balance.balanceCents != null).toList();
    if (usable.length <= BalanceHistoryChart.maxPoints) return usable;

    final step = (usable.length - 1) / (BalanceHistoryChart.maxPoints - 1);
    return [
      for (var i = 0; i < BalanceHistoryChart.maxPoints; i++)
        usable[(i * step).round()],
    ];
  }

  void _select(Offset localPosition, double width) {
    if (_points.length < 2 || width <= 0) return;
    final fraction = (localPosition.dx / width).clamp(0.0, 1.0);
    final index = (fraction * (_points.length - 1)).round();
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
    widget.onSelectionChanged?.call(_points[index]);
  }

  void _clear() {
    if (_selectedIndex == null) return;
    setState(() => _selectedIndex = null);
    widget.onSelectionChanged?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    if (_points.length < 2) return const SizedBox.shrink();

    return Semantics(
      label: widget.semanticLabel,
      image: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPressStart: (details) =>
                _select(details.localPosition, width),
            onLongPressMoveUpdate: (details) =>
                _select(details.localPosition, width),
            onLongPressEnd: (_) => _clear(),
            onHorizontalDragStart: (details) =>
                _select(details.localPosition, width),
            onHorizontalDragUpdate: (details) =>
                _select(details.localPosition, width),
            onHorizontalDragEnd: (_) => _clear(),
            onHorizontalDragCancel: _clear,
            child: CustomPaint(
              painter: _BalanceHistoryPainter(
                values: _points
                    .map((balance) => balance.balanceCents!.toDouble())
                    .toList(),
                color: widget.color,
                selectedIndex: _selectedIndex,
                guideColor: SureColors.of(context).palette.textSubdued,
                ringColor: SureColors.of(context).palette.container,
              ),
              child: const SizedBox.expand(),
            ),
          );
        },
      ),
    );
  }
}

class _BalanceHistoryPainter extends CustomPainter {
  _BalanceHistoryPainter({
    required this.values,
    required this.color,
    required this.selectedIndex,
    required this.guideColor,
    required this.ringColor,
  });

  final List<double> values;
  final Color color;
  final int? selectedIndex;
  final Color guideColor;
  final Color ringColor;

  // Vertical breathing room so the line never touches the card edges.
  static const double _inset = 6;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    var minValue = values.first;
    var maxValue = values.first;
    for (final value in values) {
      if (value < minValue) minValue = value;
      if (value > maxValue) maxValue = value;
    }
    final range = maxValue - minValue;
    final drawHeight = size.height - _inset * 2;

    Offset pointAt(int index) {
      final x = size.width * (index / (values.length - 1));
      final normalized = range == 0 ? 0.5 : (values[index] - minValue) / range;
      return Offset(x, _inset + drawHeight - normalized * drawHeight);
    }

    final line = Path();
    for (var i = 0; i < values.length; i++) {
      final point = pointAt(i);
      i == 0
          ? line.moveTo(point.dx, point.dy)
          : line.lineTo(point.dx, point.dy);
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
        ..strokeWidth = 1.75
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final selected = selectedIndex;
    if (selected != null && selected >= 0 && selected < values.length) {
      final point = pointAt(selected);
      canvas.drawLine(
        Offset(point.dx, 0),
        Offset(point.dx, size.height),
        Paint()
          ..color = guideColor.withValues(alpha: 0.6)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(point, 5.5, Paint()..color = ringColor);
      canvas.drawCircle(point, 3.75, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _BalanceHistoryPainter oldDelegate) {
    return !listEquals(oldDelegate.values, values) ||
        oldDelegate.color != color ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.guideColor != guideColor ||
        oldDelegate.ringColor != ringColor;
  }
}
