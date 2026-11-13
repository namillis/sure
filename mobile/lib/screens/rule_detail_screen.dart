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
import '../utils/rule_text.dart';
import '../widgets/open_on_web_action.dart';
import '../widgets/ds/ds.dart';
import '../widgets/sure_button.dart';
import 'rule_editor_sheet.dart';

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
/// (`GET /api/v1/rule_runs?rule_id=`). On a Sure+ server with `rules.write`
/// it can apply the rule to past transactions (two-step confirm), edit,
/// duplicate and delete it; elsewhere editing opens `/rules/:id/edit` on
/// the web.
class RuleDetailScreen extends StatefulWidget {
  const RuleDetailScreen({
    super.key,
    required this.ruleId,
    this.initialRule,
    this.initialWarnings = const [],
    this.service,
    this.accessTokenLoader,
    this.onUnauthorized,
    this.nameLookup,
    this.editorChoices,
  });

  final String ruleId;

  /// Shown while the fresh copy loads.
  final Rule? initialRule;

  /// Save `warnings` to show on open (a just-duplicated rule).
  final List<String> initialWarnings;
  final RulesService? service;

  /// Defaults to [AuthProvider.getValidAccessToken].
  final Future<String?> Function()? accessTokenLoader;

  /// Defaults to [AuthProvider.logout].
  final Future<void> Function()? onUnauthorized;

  /// Defaults to [ruleNameLookupFromProviders].
  final RuleNameLookup? nameLookup;

  /// What the editor's pickers offer; defaults to the app's providers.
  final RuleEditorChoices? editorChoices;

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

  late List<String> _warnings = widget.initialWarnings;
  bool _applying = false;

  /// Result or error of the last apply, under the button.
  String? _applyMessage;
  bool _applyFailed = false;
  bool _deleting = false;

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

  /// Runs a write with a fresh token; 401 signs out.
  Future<Map<String, dynamic>> _write(
    Future<Map<String, dynamic>> Function(String token) call,
  ) async {
    final token = await _token();
    if (token == null) {
      await _unauthorized();
      return {'success': false, 'error': 'unauthorized'};
    }
    final result = await call(token);
    if (result['error'] == 'unauthorized') await _unauthorized();
    return result;
  }

  /// The message for a failed write.
  String _failureText(AppLocalizations l, Map<String, dynamic> result) {
    if (result['code'] == 'insufficient_scope') return l.spmReadOnlyAccess;
    if (result['code'] == 'rules_running') return l.sprRuleApplyRunning;
    if (result['error'] == 'unauthorized') return l.manageActionFailed;
    return result['error']?.toString() ?? l.manageActionFailed;
  }

  RuleEditorChoices _choices() =>
      widget.editorChoices ?? RuleEditorChoices.fromProviders(context);

  Future<void> _edit(Rule rule) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = await showRuleEditorSheet(
      context,
      existing: rule,
      choices: _choices(),
      save: (body) => _write((token) =>
          _service.updateRule(accessToken: token, id: rule.id, body: body)),
    );
    if (result == null || !mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l.sprRuleSaved)));
    setState(() {
      _rule = result.rule;
      _warnings = result.warnings;
    });
    await _load();
  }

  /// Opens the editor prefilled as a new rule; the copy then replaces this
  /// screen, so back still leads to the list.
  Future<void> _duplicate(Rule rule) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final result = await showRuleEditorSheet(
      context,
      copyOf: rule,
      choices: _choices(),
      save: (body) => _write(
          (token) => _service.createRule(accessToken: token, body: body)),
    );
    if (result == null || !mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l.sprRuleSaved)));
    navigator.pushReplacement(MaterialPageRoute<void>(
      builder: (_) => RuleDetailScreen(
        ruleId: result.rule.id,
        initialRule: result.rule,
        initialWarnings: result.warnings,
        service: widget.service,
        accessTokenLoader: widget.accessTokenLoader,
        onUnauthorized: widget.onUnauthorized,
        nameLookup: widget.nameLookup,
        editorChoices: widget.editorChoices,
      ),
    ));
  }

  Future<void> _delete(Rule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final dl = AppLocalizations.of(context);
        final palette = SureColors.of(context).palette;
        return AlertDialog(
          title: Text(dl.sprRuleDeleteTitle),
          content: Text(dl.sprRuleDeleteBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(dl.commonCancel),
            ),
            TextButton(
              key: const ValueKey('ruleDeleteConfirm'),
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: palette.destructive),
              child: Text(dl.commonDelete),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _deleting = true);
    final result = await _write(
        (token) => _service.deleteRule(accessToken: token, id: rule.id));
    if (!mounted) return;
    setState(() => _deleting = false);
    if (result['success'] == true) {
      messenger.showSnackBar(SnackBar(content: Text(l.sprRuleDeleted)));
      navigator.maybePop();
    } else {
      messenger.showSnackBar(SnackBar(content: Text(_failureText(l, result))));
    }
  }

  /// Apply to past transactions: the first call only returns what the
  /// confirmation shows (422 `confirmation_required`); after the user
  /// confirms, the second call with `confirm: true` runs the rule.
  Future<void> _apply(Rule rule) async {
    final l = AppLocalizations.of(context);
    setState(() {
      _applying = true;
      _applyMessage = null;
      _applyFailed = false;
    });
    final first = await _write(
        (token) => _service.applyRule(accessToken: token, id: rule.id));
    if (!mounted) return;
    final confirmation = first['confirmation'];
    if (first['code'] != 'confirmation_required' ||
        confirmation is! RuleApplyConfirmation) {
      return _finishApply(l, first);
    }
    setState(() => _applying = false);
    final confirmed = await _confirmApply(confirmation);
    if (confirmed != true || !mounted) return;
    setState(() => _applying = true);
    final second = await _write((token) =>
        _service.applyRule(accessToken: token, id: rule.id, confirm: true));
    if (!mounted) return;
    await _finishApply(l, second);
  }

  Future<void> _finishApply(
      AppLocalizations l, Map<String, dynamic> result) async {
    final run = result['run'];
    setState(() {
      _applying = false;
      _applyFailed = run is! RuleRun;
      _applyMessage = run is RuleRun
          ? l.sprRuleApplied(run.transactionsModified)
          : _failureText(l, result);
    });
    // Apply also switches the rule on; refresh it and Recent runs.
    if (run is RuleRun) await _load();
  }

  Future<bool?> _confirmApply(RuleApplyConfirmation c) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        final dl = AppLocalizations.of(context);
        final locale = Localizations.localeOf(context).toString();
        final cost = c.estimatedAiCost;
        final lines = [
          dl.sprRuleApplyCount(c.affectedCount),
          if (c.activeRulesAboveCount > 0)
            dl.sprRuleApplyAbove(c.activeRulesAboveCount),
          if (c.autoCategorize)
            cost == null
                ? dl.sprRuleApplyAiNoCost
                : dl.sprRuleApplyAiCost(NumberFormat.currency(
                        locale: locale, name: 'USD', symbol: r'$',
                        decimalDigits: 4)
                    .format(cost)),
        ];
        return AlertDialog(
          title: Text(dl.sprRuleApplyTitle),
          content: Text(lines.join('\n\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(dl.commonCancel),
            ),
            TextButton(
              key: const ValueKey('ruleApplyConfirm'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(dl.sprRuleApplyConfirm),
            ),
          ],
        );
      },
    );
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
    final canWrite = rulesWriteEnabled(context);
    final text = RuleText(l,
        lookup: widget.nameLookup ?? ruleNameLookupFromProviders(context));

    final List<Widget> slivers;
    if (rule == null && _loading) {
      slivers = const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else if (rule == null) {
      slivers = [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: _notFound
                ? SureEmptyState(
                    icon: SureIcons.listChecks, title: l.p3roRuleNotFound)
                : SureEmptyState(
                    icon: SureIcons.circleAlert,
                    title: l.p3roRuleLoadFailed,
                    secondaryLabel: l.commonTryAgain,
                    onSecondary: _load,
                  ),
          ),
        ),
      ];
    } else {
      slivers = [
        SliverList.list(children: [
          for (final warning in _warnings)
            SureBanner(
              message: warning,
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            ),
          ..._ruleBody(context, rule, text, canWrite: canWrite),
          if (canWrite) ..._writeControls(context, rule),
        ]),
      ];
    }

    return SureLargeTitleScaffold(
      title: rule == null ? l.p3roRuleTitle : text.title(rule),
      // The detail opens from the Rules list.
      leading: Navigator.of(context).canPop()
          ? SureBackButton(label: l.shellRules)
          : null,
      actions: [
        if (!_notFound && !canWrite)
          SureNavIconButton(
            icon: SureIcons.arrowUpRight,
            semanticLabel: l.manageEditOnWeb,
            color: SureColors.of(context).palette.link,
            onPressed: () => openWebFallback(context,
                title: l.shellRules,
                path: RuleDetailScreen.webPath(widget.ruleId)),
          ),
      ],
      onRefresh: _load,
      slivers: slivers,
    );
  }

  List<Widget> _ruleBody(BuildContext context, Rule rule, RuleText text,
      {bool canWrite = false}) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final effective = rule.effectiveDate;

    return [
      SurePanel.rows(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    text.resourceType(rule.resourceType),
                    rule.active ? l.p3roRuleActive : l.p3roRuleInactive,
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color:
                        rule.active ? palette.success : palette.textSubdued,
                  ),
                ),
                if (effective != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      l.p3roRuleEffectiveFrom(
                          SureDates.shortOf(context, effective)),
                      style: TextStyle(
                          fontSize: 13, color: palette.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      if (canWrite) _applyControl(context, rule),
      SureSectionHeader(label: l.p3roRuleConditions),
      SurePanel.rows(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          if (rule.conditions.isEmpty) _Line(l.p3roRuleAllTransactions),
          for (final c in rule.conditions)
            if (c.isCompound) ...[
              _Line(text.compoundHeading(c), secondary: true),
              for (final sub in c.subConditions)
                _Line(text.condition(sub), indent: 16),
            ] else
              _Line(text.condition(c)),
        ],
      ),
      SureSectionHeader(label: l.p3roRuleActions),
      SurePanel.rows(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        children: [for (final a in rule.actions) _Line(text.action(a))],
      ),
      SureSectionHeader(label: l.p3roRuleRecentRuns),
      ..._runRows(context),
    ];
  }

  /// "Apply to past transactions" with its progress and result line.
  Widget _applyControl(BuildContext context, Rule rule) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final message = _applying ? l.sprRuleApplying : _applyMessage;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SureButton(
            key: const ValueKey('ruleApply'),
            label: l.sprRuleApply,
            fullWidth: true,
            loading: _applying,
            onPressed: _deleting ? null : () => _apply(rule),
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: _applying
                        ? palette.textSecondary
                        : _applyFailed
                            ? palette.destructive
                            : palette.success,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Footer links: Edit · Duplicate · Delete.
  List<Widget> _writeControls(BuildContext context, Rule rule) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final enabled = !_applying && !_deleting;
    Widget link(String label, VoidCallback onTap, {Key? key, Color? color}) =>
        TextButton(
          key: key,
          onPressed: enabled ? onTap : null,
          style: TextButton.styleFrom(
            foregroundColor: color ?? palette.link,
            minimumSize: const Size(44, 44),
          ),
          child: Text(label, style: const TextStyle(fontSize: 15)),
        );
    Widget dot() => Text('·', style: TextStyle(color: palette.textSubdued));

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            link(l.sprRuleEditLink, () => _edit(rule),
                key: const ValueKey('ruleEdit')),
            dot(),
            link(l.sprRuleDuplicate, () => _duplicate(rule),
                key: const ValueKey('ruleDuplicate')),
            dot(),
            link(l.sprRuleDelete, () => _delete(rule),
                key: const ValueKey('ruleDelete'), color: palette.destructive),
          ],
        ),
      ),
    ];
  }

  List<Widget> _runRows(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final locale = Localizations.localeOf(context).toString();
    final runs = _runs;
    final secondary = TextStyle(fontSize: 13, color: palette.textSecondary);
    const margin = EdgeInsets.symmetric(horizontal: 16);

    if (runs == null) {
      if (!_runsFailed) return const [];
      return [
        Padding(
          padding: margin,
          child: Text(l.p3roRuleRunsLoadFailed, style: secondary),
        ),
      ];
    }
    if (runs.isEmpty) {
      return [
        Padding(
          padding: margin,
          child: Text(l.p3roRuleNoRuns, style: secondary),
        ),
      ];
    }

    return [
      SurePanel.rows(
        margin: margin,
        children: [
          for (final run in runs)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          [
                            if (run.executedAt != null)
                              '${SureDates.shortOf(context, run.executedAt!.toLocal())}, '
                                  '${DateFormat.jm(locale).format(run.executedAt!.toLocal())}',
                            if (run.executionType == 'manual')
                              l.p3roRuleRunManual,
                            if (run.executionType == 'scheduled')
                              l.p3roRuleRunScheduled,
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        switch (run.status) {
                          'success' => l.p3roRuleRunSuccess,
                          'failed' => l.p3roRuleRunFailed,
                          _ => l.p3roRuleRunPending,
                        },
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: switch (run.status) {
                            'success' => palette.success,
                            'failed' => palette.destructive,
                            _ => palette.textSecondary,
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    run.status == 'pending'
                        ? l.p3roRuleRunQueued(run.transactionsQueued)
                        : l.p3roRuleRunCounts(run.transactionsModified,
                            run.transactionsProcessed),
                    style: secondary,
                  ),
                  if (run.errorMessage != null &&
                      run.errorMessage!.isNotEmpty)
                    Text(run.errorMessage!,
                        style: TextStyle(
                            fontSize: 13, color: palette.destructive)),
                ],
              ),
            ),
        ],
      ),
    ];
  }
}

/// One condition or action sentence as a panel row.
class _Line extends StatelessWidget {
  const _Line(this.value, {this.indent = 0, this.secondary = false});

  final String value;
  final double indent;

  /// A compound heading ("Any of these match") in `textSecondary`.
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(14 + indent, 11, 14, 11),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 15,
              color: secondary ? palette.textSecondary : palette.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
