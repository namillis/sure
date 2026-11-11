import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/insight.dart';
import '../providers/auth_provider.dart';
import '../services/insights_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../widgets/manage_widgets.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_card.dart';

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

    final List<Widget> children;
    switch (_state) {
      case _State.loading:
        children = const [
          Padding(
            padding: EdgeInsets.only(top: 96),
            child: Center(child: CircularProgressIndicator()),
          ),
        ];
      case _State.unavailable:
        children = [
          ManageMessage(
            icon: Icons.lightbulb_outline,
            title: l.p3roInsightsUnavailable,
            body: l.p3roInsightsUnavailableBody,
          ),
        ];
      case _State.failed:
        children = [
          ManageMessage(
            icon: Icons.error_outline,
            title: l.p3roInsightsLoadFailed,
            onRetry: _load,
          ),
        ];
      case _State.ready:
        children = _insights.isEmpty
            ? [
                ManageMessage(
                  icon: Icons.lightbulb_outline,
                  title: l.p3roInsightsEmpty,
                  body: l.p3roInsightsEmptyBody,
                ),
              ]
            : [
                for (final insight in _insights)
                  Dismissible(
                    key: ValueKey('insight-${insight.id}'),
                    direction: DismissDirection.endToStart,
                    background: const _DismissBackground(),
                    onDismissed: (_) => _dismiss(insight),
                    child: _InsightCard(
                      insight: insight,
                      onDismiss: () => _dismiss(insight),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(SureSpacing.lg),
                  child: Text(
                    l.p3roInsightsDismissHint,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SureColors.of(context).palette.textSubdued),
                  ),
                ),
              ];
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.insightsTitle)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(
              top: SureSpacing.md, bottom: SureSpacing.huge),
          children: children,
        ),
      ),
    );
  }
}

class _DismissBackground extends StatelessWidget {
  const _DismissBackground();

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 32),
      child: Icon(Icons.check, color: palette.textSecondary),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight, required this.onDismiss});

  final Insight insight;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = SureColors.of(context).palette;
    final generated = insight.generatedAt;
    final locale = Localizations.localeOf(context).toString();

    return SureCard(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(insight.title,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
          if (insight.priority == 'high' || generated != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                [
                  if (insight.priority == 'high') l.insightsPriorityHigh,
                  if (generated != null)
                    DateFormat.yMMMd(locale).format(generated.toLocal()),
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                    color: insight.priority == 'high'
                        ? palette.warning
                        : palette.textSecondary),
              ),
            ),
          if (insight.body.isNotEmpty) ...[
            const SizedBox(height: SureSpacing.md),
            Text(insight.body,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: palette.textSecondary)),
          ],
          const SizedBox(height: SureSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: SureButton(
                label: l.insightsDismiss,
                variant: SureButtonVariant.outline,
                onPressed: onDismiss,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
