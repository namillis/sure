import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/spending_vs_normal.dart';
import '../providers/auth_provider.dart';
import '../screens/reports_screen.dart';
import '../services/spending_vs_normal_service.dart';
import '../theme/sure_colors.dart';
import 'ds/sure_panel.dart';
import 'sure_icon.dart';
import 'sure_list_group.dart';

/// Home's one-row "Spending 13% above normal ›" panel, from
/// `GET /api/v1/spending_vs_normal`. Tapping opens [ReportsScreen], whose
/// Month view flags the categories above normal. Renders nothing while
/// loading, on any error, or when there is no history to compare with. Give
/// it a new key to reload.
class SpendingVsNormalCard extends StatefulWidget {
  const SpendingVsNormalCard({
    super.key,
    this.service,
    this.accessTokenLoader,
    this.onOpen,
    this.margin,
    this.inGroup = false,
  });

  /// Injected for tests; otherwise the card owns one.
  final SpendingVsNormalService? service;

  /// Defaults to [AuthProvider.getValidAccessToken].
  final Future<String?> Function()? accessTokenLoader;

  /// Replaces opening [ReportsScreen] (tests).
  final VoidCallback? onOpen;
  final EdgeInsetsGeometry? margin;

  /// Renders just the row with a hairline under it (no panel), for a parent
  /// [SurePanel] that groups several one-line rows. Nothing at all renders
  /// when there is nothing to compare, so the hairline never dangles.
  final bool inGroup;

  /// Ratios closer to zero than this read as "about normal".
  static const double aboutNormal = 0.005;

  @override
  State<SpendingVsNormalCard> createState() => _SpendingVsNormalCardState();
}

class _SpendingVsNormalCardState extends State<SpendingVsNormalCard> {
  late final SpendingVsNormalService _service;
  SpendingVsNormal? _data;

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

  void _open() {
    final onOpen = widget.onOpen;
    if (onOpen != null) return onOpen();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ReportsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null || !data.comparable || data.categories.isEmpty) {
      return const SizedBox.shrink();
    }

    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final percent =
        NumberFormat.percentPattern(Localizations.localeOf(context).toString());
    final ratio = data.ratio;
    final above = ratio != null && ratio >= SpendingVsNormalCard.aboutNormal;

    final String title;
    if (ratio == null) {
      title = l.spendingVsNormalTitle;
    } else if (ratio.abs() < SpendingVsNormalCard.aboutNormal) {
      title = l.dshSpendingAboutNormal;
    } else if (ratio > 0) {
      title = l.dshSpendingAbove(percent.format(ratio));
    } else {
      title = l.dshSpendingBelow(percent.format(-ratio));
    }

    final tint = above ? palette.warning : palette.textSecondary;
    final row = SureListRow(
      leading: ExcludeSemantics(
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: above
                ? palette.warning.withValues(alpha: 0.15)
                : palette.surfaceInset,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: SureIcon(
            ratio != null && ratio < 0
                ? SureIcons.trendingDown
                : SureIcons.trendingUp,
            size: 15,
            color: tint,
          ),
        ),
      ),
      title: title,
      showChevron: true,
      onTap: _open,
    );
    if (widget.inGroup) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        row,
        const SureHairline(indent: SurePanel.iconRowDividerIndent),
      ]);
    }
    return SurePanel.rows(margin: widget.margin, children: [row]);
  }
}
