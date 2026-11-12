import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/insight.dart';
import '../providers/auth_provider.dart';
import '../services/insights_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../widgets/ds/ds.dart';

/// Every visible insight from `GET /api/v1/insights`. Swipe one away or tap
/// Dismiss to acknowledge it: the row leaves at once and comes back with a
/// snackbar if the server refuses. Insights are a web preview feature, so a
/// 403/404 shows an explanation instead of an error.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({
    super.key,
    this.service,
    this.accessTokenLoader,
    this.onUnauthorized,
  });

  final InsightsService? service;

  /// Defaults to [AuthProvider.getValidAccessToken].
  final Future<String?> Function()? accessTokenLoader;

  /// Defaults to [AuthProvider.logout].
  final Future<void> Function()? onUnauthorized;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

enum _State { loading, ready, unavailable, failed }

class _InsightsScreenState extends State<InsightsScreen> {
  late final InsightsService _service;
  List<Insight> _insights = const [];
  _State _state = _State.loading;

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

  Future<void> _unauthorized() async {
    final handler = widget.onUnauthorized;
    if (handler != null) return handler();
    await context.read<AuthProvider>().logout();
  }

  Future<void> _load() async {
    final token = await _token();
    if (!mounted) return;
    if (token == null) return _unauthorized();
    final result = await _service.getInsights(accessToken: token);
    if (!mounted) return;
    if (result['error'] == 'unauthorized') return _unauthorized();
    setState(() {
      if (result['success'] == true) {
        _insights = (result['insights'] as List<dynamic>).cast<Insight>();
        _state = _State.ready;
      } else if (result['error'] == 'unavailable') {
        _state = _State.unavailable;
      } else if (_state != _State.ready) {
        _state = _State.failed;
      }
    });
    if (result['success'] != true &&
        result['error'] != 'unavailable' &&
        _state == _State.ready) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).p3roInsightsLoadFailed)));
    }
  }

  /// Removes [insight] now and puts it back where it was if the server fails.
  Future<void> _dismiss(Insight insight) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context).insightsDismissFailed;
    final index = _insights.indexWhere((i) => i.id == insight.id);
    if (index < 0) return;
    setState(() => _insights = [..._insights]..removeAt(index));

    final token = await _token();
    if (!mounted) return;
    if (token == null) return _unauthorized();
    final result =
        await _service.acknowledge(accessToken: token, id: insight.id);
    if (!mounted) return;
    if (result['error'] == 'unauthorized') return _unauthorized();
    if (result['success'] == true) return;

    setState(() {
      if (_insights.any((i) => i.id == insight.id)) return;
      final restored = [..._insights];
      restored.insert(index.clamp(0, restored.length), insight);
      _insights = restored;
    });
    messenger.showSnackBar(SnackBar(content: Text(failed)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;

    final List<Widget> slivers;
    switch (_state) {
      case _State.loading:
        slivers = const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          ),
        ];
      case _State.unavailable:
        slivers = [
          _centered(SureEmptyState(
            icon: SureIcons.lightbulb,
            title: l.p3roInsightsUnavailable,
            body: l.p3roInsightsUnavailableBody,
          )),
        ];
      case _State.failed:
        slivers = [
          _centered(SureEmptyState(
            icon: SureIcons.circleAlert,
            title: l.p3roInsightsLoadFailed,
            secondaryLabel: l.commonTryAgain,
            onSecondary: _load,
          )),
        ];
      case _State.ready:
        slivers = _insights.isEmpty
            ? [
                _centered(SureEmptyState(
                  icon: SureIcons.lightbulb,
                  title: l.p3roInsightsEmpty,
                  body: l.p3roInsightsEmptyBody,
                )),
              ]
            : [
                SliverPadding(
                  padding: const EdgeInsets.only(top: 8),
                  sliver: SliverList.list(
                    children: [
                      for (final insight in _insights)
                        Dismissible(
                          key: ValueKey('insight-${insight.id}'),
                          direction: DismissDirection.endToStart,
                          background: const _DismissBackground(),
                          onDismissed: (_) => _dismiss(insight),
                          child: _InsightPanel(
                            insight: insight,
                            onDismiss: () => _dismiss(insight),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                        child: Text(
                          l.p3roInsightsDismissHint,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12, color: palette.textSubdued),
                        ),
                      ),
                    ],
                  ),
                ),
              ];
    }

    return SureLargeTitleScaffold(
      title: l.insightsTitle,
      // Insights opens from Home's insight row.
      leading: Navigator.of(context).canPop()
          ? SureBackButton(label: l.navHome)
          : null,
      onRefresh: _load,
      slivers: slivers,
    );
  }

  Widget _centered(Widget state) => SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: state),
      );
}

class _DismissBackground extends StatelessWidget {
  const _DismissBackground();

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 32),
      child: SureIcon(SureIcons.check, size: 22, color: palette.textSecondary),
    );
  }
}

/// Fill and glyph color of an insight's icon: warning for high priority,
/// link for medium, neutral for low.
(Color fill, Color glyph) insightTint(
    SureTokenPalette palette, String priority) {
  return switch (priority) {
    'high' => (palette.warning.withValues(alpha: 0.15), palette.warning),
    'medium' => (palette.link.withValues(alpha: 0.14), palette.link),
    _ => (palette.surfaceInset, palette.textSecondary),
  };
}

class _InsightPanel extends StatelessWidget {
  const _InsightPanel({required this.insight, required this.onDismiss});

  final Insight insight;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final generated = insight.generatedAt;
    final (fill, glyph) = insightTint(palette, insight.priority);
    final meta = [
      if (insight.priority == 'high') l.insightsPriorityHigh,
      if (generated != null) SureDates.shortOf(context, generated.toLocal()),
    ].join(' · ');

    return SurePanel(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              key: ValueKey('insightIcon-${insight.id}'),
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: SureIcon(SureIcons.lightbulb, size: 15, color: glyph),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
                if (meta.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      meta,
                      style: TextStyle(
                        fontSize: 12,
                        color: insight.priority == 'high'
                            ? palette.warning
                            : palette.textSecondary,
                      ),
                    ),
                  ),
                if (insight.body.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      insight.body,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                // A quiet text action; swiping the panel does the same.
                TextButton(
                  onPressed: onDismiss,
                  style: TextButton.styleFrom(
                    foregroundColor: palette.link,
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    alignment: AlignmentDirectional.centerStart,
                  ),
                  child: Text(
                    l.insightsDismiss,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
