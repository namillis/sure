import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/insight.dart';
import '../providers/auth_provider.dart';
import '../screens/insights_screen.dart';
import '../services/insights_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import 'sure_button.dart';
import 'sure_card.dart';

/// Home card with the top [maxItems] insights from `GET /api/v1/insights`.
/// Tap one to read it and dismiss it. Renders nothing while loading, when
/// there are none, or when the endpoint fails or is disabled (insights are a
/// web preview feature, so 403 is normal). Give it a new key to reload.
/// With more than [maxItems] insights, "See all" opens [InsightsScreen].
class InsightsCard extends StatefulWidget {
  const InsightsCard({
    super.key,
    this.service,
    this.accessTokenLoader,
    this.maxItems = 3,
  });

  /// Injected for tests; otherwise the card owns one.
  final InsightsService? service;

  /// Defaults to [AuthProvider.getValidAccessToken].
  final Future<String?> Function()? accessTokenLoader;
  final int maxItems;

  @override
  State<InsightsCard> createState() => _InsightsCardState();
}

class _InsightsCardState extends State<InsightsCard> {
  late final InsightsService _service;
  List<Insight> _insights = const [];
  String? _expandedId;
  final Set<String> _dismissing = {};

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
    setState(() => _insights = (result['insights'] as List<dynamic>).cast<Insight>());
  }

  Future<void> _dismiss(Insight insight) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final failed = AppLocalizations.of(context).insightsDismissFailed;
    setState(() => _dismissing.add(insight.id));
    final token = await _token();
    final result = token == null
        ? const {'success': false}
        : await _service.acknowledge(accessToken: token, id: insight.id);
    if (!mounted) return;
    setState(() {
      _dismissing.remove(insight.id);
      if (result['success'] == true) {
        _insights = _insights.where((i) => i.id != insight.id).toList();
      }
    });
    if (result['success'] != true) {
      messenger?.showSnackBar(SnackBar(content: Text(failed)));
    }
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
    final shown = _insights.take(widget.maxItems).toList();
    if (shown.isEmpty) return const SizedBox.shrink();

    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = SureColors.of(context).palette;

    return SureCard(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 18, color: palette.textSecondary),
              const SizedBox(width: SureSpacing.sm),
              Expanded(
                child: Text(l.insightsTitle,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: palette.textSecondary)),
              ),
              if (_insights.length > widget.maxItems)
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  onPressed: _openAll,
                  child: Text(l.p3roInsightsSeeAll),
                ),
            ],
          ),
          for (final insight in shown)
            _InsightTile(
              insight: insight,
              expanded: _expandedId == insight.id,
              dismissing: _dismissing.contains(insight.id),
              onToggle: () => setState(() =>
                  _expandedId = _expandedId == insight.id ? null : insight.id),
              onDismiss: () => _dismiss(insight),
            ),
        ],
      ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({
    required this.insight,
    required this.expanded,
    required this.dismissing,
    required this.onToggle,
    required this.onDismiss,
  });

  final Insight insight;
  final bool expanded;
  final bool dismissing;
  final VoidCallback onToggle;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = SureColors.of(context).palette;
    final high = insight.priority == 'high';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: expanded,
          hint: expanded ? l.insightsHideDetails : l.insightsShowDetails,
          child: InkWell(
            onTap: onToggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: SureSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            insight.title,
                            maxLines: expanded ? null : 2,
                            overflow: expanded ? null : TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (high)
                            Text(
                              l.insightsPriorityHigh,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: palette.warning),
                            ),
                        ],
                      ),
                    ),
                    ExcludeSemantics(
                      child: Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: !expanded
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(right: SureSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (insight.body.isNotEmpty)
                        Text(insight.body,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: palette.textSecondary)),
                      const SizedBox(height: SureSpacing.md),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: SureButton(
                          label: l.insightsDismiss,
                          variant: SureButtonVariant.outline,
                          loading: dismissing,
                          onPressed: onDismiss,
                        ),
                      ),
                      const SizedBox(height: SureSpacing.md),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
