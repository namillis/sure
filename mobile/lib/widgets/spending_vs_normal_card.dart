import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/spending_vs_normal.dart';
import '../providers/auth_provider.dart';
import '../providers/privacy_provider.dart';
import '../services/spending_vs_normal_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../utils/investment_math.dart';
import '../utils/money_masker.dart';
import 'budget_progress_bar.dart' show parseCategoryColor;
import 'sure_card.dart';

/// Home card comparing this month's spending with normal (from
/// `GET /api/v1/spending_vs_normal`), with the categories furthest above
/// normal. Tap to expand to every category. Renders nothing while loading,
/// on any error, or when there is no history to compare with. Give it a new
/// key to reload.
class SpendingVsNormalCard extends StatefulWidget {
  const SpendingVsNormalCard({
    super.key,
    this.service,
    this.accessTokenLoader,
  });

  /// Injected for tests; otherwise the card owns one.
  final SpendingVsNormalService? service;

  /// Defaults to [AuthProvider.getValidAccessToken].
  final Future<String?> Function()? accessTokenLoader;

  @override
  State<SpendingVsNormalCard> createState() => _SpendingVsNormalCardState();
}

class _SpendingVsNormalCardState extends State<SpendingVsNormalCard> {
  late final SpendingVsNormalService _service;
  SpendingVsNormal? _data;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? SpendingVsNormalService();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  Future<void> _load() async {
    final loader = widget.accessTokenLoader;
    final token = await (loader != null
        ? loader()
        : context.read<AuthProvider>().getValidAccessToken());
    if (token == null || !mounted) return;
    final result = await _service.getSpendingVsNormal(accessToken: token);
    if (!mounted || result['success'] != true) return;
    setState(() => _data = result['spending'] as SpendingVsNormal);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null || !data.comparable || data.categories.isEmpty) {
      return const SizedBox.shrink();
    }

    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = SureColors.of(context).palette;
    final locale = Localizations.localeOf(context).toString();
    final hidden = context.watch<PrivacyProvider>().hidden;
    final percentFormat = NumberFormat.percentPattern(locale);

    String money(double value) => MoneyMasker.mask(
          InvestmentMath.formatMoney(value, currency: data.currency, locale: locale),
          hidden: hidden,
        );
    String signedPercent(double ratio) =>
        '${ratio > 0 ? '+' : ''}${percentFormat.format(ratio)}';

    final ratio = data.ratio;
    final summary = [
      if (data.normalTotal != null) l.spendingVsNormalNormal(money(data.normalTotal!)),
      if (ratio != null && ratio.abs() >= 0.005)
        ratio > 0
            ? l.spendingVsNormalAbove(percentFormat.format(ratio))
            : l.spendingVsNormalBelow(percentFormat.format(-ratio)),
    ].join(' · ');
    final top = data.topAboveNormal();

    return SureCard(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
      onTap: () => setState(() => _expanded = !_expanded),
      child: Semantics(
        button: true,
        expanded: _expanded,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l.spendingVsNormalTitle,
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: palette.textSecondary)),
                ),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                    color: palette.textSecondary),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              data.inProgress
                  ? l.spendingVsNormalSoFar(money(data.total))
                  : money(data.total),
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (summary.isNotEmpty)
              Text(summary,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: palette.textSecondary)),
            if (!_expanded && top.isNotEmpty) ...[
              const SizedBox(height: SureSpacing.md),
              Wrap(
                spacing: SureSpacing.lg,
                runSpacing: SureSpacing.xs,
                children: [
                  for (final c in top)
                    Text(
                      '${c.name} ${c.ratio == null ? l.spendingVsNormalNew : signedPercent(c.ratio!)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: palette.warning, fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ],
            if (_expanded) ...[
              const SizedBox(height: SureSpacing.md),
              for (final c in data.categories)
                _CategoryLine(
                  category: c,
                  amount: c.normal == null
                      ? money(c.total)
                      : l.spendingVsNormalCategoryNormal(
                          money(c.total), money(c.normal!)),
                  change: c.ratio == null
                      ? (c.total > 0 && (c.normal ?? 0) == 0
                          ? l.spendingVsNormalNew
                          : '')
                      : signedPercent(c.ratio!),
                ),
            ],
            const SizedBox(height: SureSpacing.xs),
            Text(
              _expanded ? l.spendingVsNormalShowLess : l.spendingVsNormalShowAll,
              style: theme.textTheme.bodySmall?.copyWith(color: palette.link),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryLine extends StatelessWidget {
  const _CategoryLine({
    required this.category,
    required this.amount,
    required this.change,
  });

  final SpendingCategory category;
  final String amount;
  final String change;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = SureColors.of(context).palette;
    final above = (category.change ?? 0) >= 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SureSpacing.xs),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: parseCategoryColor(category.color) ?? palette.textSubdued,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: SureSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(category.name, style: theme.textTheme.bodyMedium),
                Text(amount,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: palette.textSecondary)),
              ],
            ),
          ),
          Text(
            change,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: above ? palette.warning : palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
