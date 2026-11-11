import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/insight.dart';
import '../providers/auth_provider.dart';
import '../screens/insights_screen.dart';
import '../services/insights_service.dart';
import '../theme/sure_colors.dart';
import 'ds/sure_panel.dart';
import 'sure_icon.dart';
import 'sure_list_group.dart';

/// Home's one-row insight panel: a warning-tinted lightbulb, the top insight
/// from `GET /api/v1/insights`, and a chevron that opens [InsightsScreen]
/// (where insights are read and dismissed). Renders nothing while loading,
/// when there are none, or when the endpoint fails or is disabled (insights
/// are a web preview feature, so 403 is normal). Give it a new key to reload.
class InsightsCard extends StatefulWidget {
  const InsightsCard({
    super.key,
    this.service,
    this.accessTokenLoader,
    this.margin,
    this.inGroup = false,
  });

  /// Injected for tests; otherwise the card owns one.
  final InsightsService? service;

  /// Defaults to [AuthProvider.getValidAccessToken].
  final Future<String?> Function()? accessTokenLoader;
  final EdgeInsetsGeometry? margin;

  /// Renders just the row with a hairline under it (no panel), for a parent
  /// [SurePanel] that groups several one-line rows. Nothing at all renders
  /// when there is no insight, so the hairline never dangles.
  final bool inGroup;

  @override
  State<InsightsCard> createState() => _InsightsCardState();
}

class _InsightsCardState extends State<InsightsCard> {
  late final InsightsService _service;
  List<Insight> _insights = const [];

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? InsightsService();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  Future<String?> _token() {
    final loader = widget.accessTokenLoader;
    if (loader != null) return loader();
    return context.read<AuthProvider>().getValidAccessToken();
  }

  Future<void> _load() async {
    final token = await _token();
    if (token == null || !mounted) return;
    final result = await _service.getInsights(accessToken: token);
    if (!mounted || result['success'] != true) return;
    setState(() =>
        _insights = (result['insights'] as List<dynamic>).cast<Insight>());
  }

  Future<void> _openAll() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => InsightsScreen(
        service: _service,
        accessTokenLoader: widget.accessTokenLoader,
      ),
    ));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_insights.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final top = _insights.first;

    final row = Semantics(
      hint: l.insightsTitle,
      child: SureListRow(
        leading: ExcludeSemantics(
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: palette.warning.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: SureIcon(
              SureIcons.lightbulb,
              size: 15,
              color: palette.warning,
            ),
          ),
        ),
        title: top.title,
        showChevron: true,
        onTap: _openAll,
      ),
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
