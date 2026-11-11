import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/rule.dart';
import '../providers/accounts_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/merchants_provider.dart';
import '../providers/tags_provider.dart';
import '../services/rules_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../utils/rule_text.dart';
import '../widgets/manage_widgets.dart';
import '../widgets/open_on_web_action.dart';
import '../widgets/sure_card.dart';

T? _maybe<T>(BuildContext context) {
  try {
    return Provider.of<T>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  }
}

/// Names the app's category, tag, merchant and account providers already
/// hold, so rule values (ids on the API) read as names. Ids the providers
/// don't know resolve to null.
RuleNameLookup ruleNameLookupFromProviders(BuildContext context) {
  final categories = _maybe<CategoriesProvider>(context)?.categories;
  final tags = _maybe<TagsProvider>(context)?.tags;
  final merchants = _maybe<MerchantsProvider>(context)?.merchants;
  final accounts = _maybe<AccountsProvider>(context)?.accounts;
  return (kind, id) => switch (kind) {
        RuleValueKind.category =>
          categories?.where((c) => c.id == id).firstOrNull?.name,
        RuleValueKind.tag => tags?.where((t) => t.id == id).firstOrNull?.name,
        RuleValueKind.merchant =>
          merchants?.where((m) => m.id == id).firstOrNull?.name,
        RuleValueKind.account =>
          accounts?.where((a) => a.id == id).firstOrNull?.name,
      };
}

/// Fetches categories, tags and merchants into their providers if they
/// haven't been yet (each provider skips a repeat fetch). Accounts are
/// already loaded by the home screen.
Future<void> loadRuleNameProviders(BuildContext context, String token) async {
  final categories = _maybe<CategoriesProvider>(context);
  final tags = _maybe<TagsProvider>(context);
  final merchants = _maybe<MerchantsProvider>(context);
  await Future.wait([
    if (categories != null) categories.fetchCategories(accessToken: token),
    if (tags != null) tags.fetchTags(accessToken: token),
    if (merchants != null) merchants.fetchMerchants(accessToken: token),
  ]);
}

/// One rule (`GET /api/v1/rules/:id`) in words, with its newest runs
/// (`GET /api/v1/rule_runs?rule_id=`). Editing opens `/rules/:id/edit` on
/// the web.
class RuleDetailScreen extends StatefulWidget {
  const RuleDetailScreen({
    super.key,
    required this.ruleId,
    this.initialRule,
    this.service,
    this.accessTokenLoader,
    this.onUnauthorized,
    this.nameLookup,
  });

  final String ruleId;

  /// Shown while the fresh copy loads.
  final Rule? initialRule;
  final RulesService? service;

  /// Defaults to [AuthProvider.getValidAccessToken].
  final Future<String?> Function()? accessTokenLoader;

  /// Defaults to [AuthProvider.logout].
  final Future<void> Function()? onUnauthorized;

  /// Defaults to [ruleNameLookupFromProviders].
  final RuleNameLookup? nameLookup;

  static String webPath(String id) => '/rules/${Uri.encodeComponent(id)}/edit';

  @override
  State<RuleDetailScreen> createState() => _RuleDetailScreenState();
}

class _RuleDetailScreenState extends State<RuleDetailScreen> {
  late final RulesService _service;
  Rule? _rule;
  bool _loading = true;
  bool _notFound = false;
  List<RuleRun>? _runs;
  bool _runsFailed = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? RulesService();
    _rule = widget.initialRule;
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
    if (mounted) setState(() => _loading = true);
    final token = await _token();
    if (!mounted) return;
    if (token == null) return _unauthorized();
    if (widget.nameLookup == null) await loadRuleNameProviders(context, token);
    if (!mounted) return;
    final results = await Future.wait([
      _service.getRule(accessToken: token, id: widget.ruleId),
      _service.listRuleRuns(accessToken: token, ruleId: widget.ruleId),
    ]);
    if (!mounted) return;
    final ruleResult = results[0];
    final runsResult = results[1];
    if (ruleResult['error'] == 'unauthorized' ||
        runsResult['error'] == 'unauthorized') {
      return _unauthorized();
    }
    setState(() {
      _loading = false;
      _notFound = ruleResult['error'] == 'not_found';
      if (ruleResult['success'] == true) _rule = ruleResult['rule'] as Rule;
      if (_notFound) _rule = null;
      _runsFailed = runsResult['success'] != true;
      if (!_runsFailed) {
        _runs = (runsResult['runs'] as List<dynamic>).cast<RuleRun>();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final rule = _rule;
    final text = RuleText(l,
        lookup: widget.nameLookup ?? ruleNameLookupFromProviders(context));

    final List<Widget> children;
    if (rule == null && _loading) {
      children = const [
        Padding(
          padding: EdgeInsets.only(top: 96),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else if (rule == null) {
      children = [
        _notFound
            ? ManageMessage(icon: Icons.rule, title: l.p3roRuleNotFound)
            : ManageMessage(
                icon: Icons.error_outline,
                title: l.p3roRuleLoadFailed,
                onRetry: _load,
              ),
      ];
    } else {
      children = _ruleBody(context, rule, text);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(rule == null ? l.p3roRuleTitle : text.title(rule)),
        actions: [
          if (!_notFound)
            IconButton(
              icon: const Icon(Icons.language),
              tooltip: l.manageEditOnWeb,
              onPressed: () => openWebFallback(context,
                  title: l.shellRules,
                  path: RuleDetailScreen.webPath(widget.ruleId)),
            ),
        ],
      ),
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

  List<Widget> _ruleBody(BuildContext context, Rule rule, RuleText text) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = SureColors.of(context).palette;
    final locale = Localizations.localeOf(context).toString();
    final secondary =
        theme.textTheme.bodySmall?.copyWith(color: palette.textSecondary);
    final effective = rule.effectiveDate;

    Widget line(String value, {double indent = 0}) => Padding(
          padding: EdgeInsets.only(left: indent, top: SureSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: theme.textTheme.bodyMedium),
              Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
            ],
          ),
        );

    return [
      _Section(
        children: [
          Text(
            [
              text.resourceType(rule.resourceType),
              rule.active ? l.p3roRuleActive : l.p3roRuleInactive,
            ].join(' · '),
            style: theme.textTheme.labelLarge?.copyWith(
                color: rule.active ? palette.success : palette.textSubdued),
          ),
          if (effective != null)
            Padding(
              padding: const EdgeInsets.only(top: SureSpacing.xs),
              child: Text(
                  l.p3roRuleEffectiveFrom(
                      DateFormat.yMMMd(locale).format(effective)),
                  style: secondary),
            ),
        ],
      ),
      _Section(
        title: l.p3roRuleConditions,
        children: [
          if (rule.conditions.isEmpty) line(l.p3roRuleAllTransactions),
          for (final c in rule.conditions)
            if (c.isCompound) ...[
              line(text.compoundHeading(c)),
              for (final sub in c.subConditions)
                line(text.condition(sub), indent: SureSpacing.xl),
            ] else
              line(text.condition(c)),
        ],
      ),
      _Section(
        title: l.p3roRuleActions,
        children: [for (final a in rule.actions) line(text.action(a))],
      ),
      _Section(
        title: l.p3roRuleRecentRuns,
        children: _runRows(context),
      ),
    ];
  }

  List<Widget> _runRows(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = SureColors.of(context).palette;
    final locale = Localizations.localeOf(context).toString();
    final secondary =
        theme.textTheme.bodySmall?.copyWith(color: palette.textSecondary);
    final runs = _runs;

    if (runs == null) {
      return [
        Text(_runsFailed ? l.p3roRuleRunsLoadFailed : '', style: secondary),
      ];
    }
    if (runs.isEmpty) return [Text(l.p3roRuleNoRuns, style: secondary)];

    return [
      for (final run in runs)
        Padding(
          padding: const EdgeInsets.only(top: SureSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      [
                        if (run.executedAt != null)
                          DateFormat.yMMMd(locale)
                              .add_jm()
                              .format(run.executedAt!.toLocal()),
                        if (run.executionType == 'manual') l.p3roRuleRunManual,
                        if (run.executionType == 'scheduled')
                          l.p3roRuleRunScheduled,
                      ].join(' · '),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    switch (run.status) {
                      'success' => l.p3roRuleRunSuccess,
                      'failed' => l.p3roRuleRunFailed,
                      _ => l.p3roRuleRunPending,
                    },
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: switch (run.status) {
                        'success' => palette.success,
                        'failed' => palette.destructive,
                        _ => palette.textSecondary,
                      },
                    ),
                  ),
                ],
              ),
              Text(
                run.status == 'pending'
                    ? l.p3roRuleRunQueued(run.transactionsQueued)
                    : l.p3roRuleRunCounts(
                        run.transactionsModified, run.transactionsProcessed),
                style: secondary,
              ),
              if (run.errorMessage != null && run.errorMessage!.isNotEmpty)
                Text(run.errorMessage!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: palette.destructive)),
            ],
          ),
        ),
    ];
  }
}

class _Section extends StatelessWidget {
  const _Section({this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = SureColors.of(context).palette;
    return SureCard(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Text(title!,
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: palette.textSecondary)),
          ...children,
        ],
      ),
    );
  }
}
