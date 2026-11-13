import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/rule.dart';
import '../providers/auth_provider.dart';
import '../providers/server_features_provider.dart';
import '../services/rules_service.dart';
import '../theme/sure_colors.dart';
import '../utils/rule_layout.dart';
import '../utils/rule_text.dart';
import '../widgets/ds/ds.dart';
import '../widgets/open_on_web_action.dart';
import 'rule_detail_screen.dart';
import 'rule_editor_sheet.dart';
import 'rule_groups_screen.dart';
import 'settings_links.dart';

/// The family's rules from `GET /api/v1/rules`, in run order. Tap one for
/// its conditions, actions and recent runs. On a Sure+ server:
/// - `rules.write`: "+" opens the rule editor; elsewhere it's the web.
/// - `rules.groups`: rules sit under their group's header, and "Manage
///   groups" opens [RuleGroupsScreen].
/// - `rules.reorder`: "Edit" turns on drag handles; a group moves as one
///   block. Without it reordering is on the web.
/// - `rules.apply_all`: "Apply all rules" with the two-step confirm.
class RulesScreen extends StatefulWidget {
  const RulesScreen({
    super.key,
    this.service,
    this.accessTokenLoader,
    this.onUnauthorized,
    this.nameLookup,
    this.editorChoices,
  });

  final RulesService? service;

  /// Defaults to [AuthProvider.getValidAccessToken].
  final Future<String?> Function()? accessTokenLoader;

  /// Defaults to [AuthProvider.logout].
  final Future<void> Function()? onUnauthorized;

  /// Names for category, tag, merchant and account ids; defaults to the
  /// app's providers (see [ruleNameLookupFromProviders]).
  final RuleNameLookup? nameLookup;

  /// What the editor's pickers offer; defaults to the app's providers.
  final RuleEditorChoices? editorChoices;

  static const webPath = '/rules';

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  late final RulesService _service;
  List<Rule>? _rules;
  bool _loading = true;

  /// `warnings` from the last save, shown until the next one.
  List<String> _warnings = const [];

  /// The blocks being reordered; null outside reorder mode.
  List<RuleBlock>? _reorder;
  List<String> _reorderStart = const [];
  bool _savingOrder = false;
  bool _applyingAll = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? RulesService();
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

  String _failureText(AppLocalizations l, Map<String, dynamic> result) {
    if (result['code'] == 'insufficient_scope') return l.spmReadOnlyAccess;
    if (result['code'] == 'rules_running') return l.sprRuleApplyRunning;
    if (result['error'] == 'unauthorized') return l.manageActionFailed;
    return result['error']?.toString() ?? l.manageActionFailed;
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final token = await _token();
    if (!mounted) return;
    if (token == null) return _unauthorized();
    if (widget.nameLookup == null) await loadRuleNameProviders(context, token);
    if (!mounted) return;
    final result = await _service.listRules(accessToken: token);
    if (!mounted) return;
    if (result['error'] == 'unauthorized') return _unauthorized();
    final ok = result['success'] == true;
    if (!ok && _rules != null) {
      _snack(AppLocalizations.of(context).p3roRulesLoadFailed);
    }
    setState(() {
      _loading = false;
      if (ok) _rules = (result['rules'] as List<dynamic>).cast<Rule>();
    });
  }

  Future<void> _open(Rule rule) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RuleDetailScreen(
        ruleId: rule.id,
        initialRule: rule,
        service: _service,
        accessTokenLoader: widget.accessTokenLoader,
        onUnauthorized: widget.onUnauthorized,
        nameLookup: widget.nameLookup,
        editorChoices: widget.editorChoices,
      ),
    ));
    // The rule may have been edited, duplicated, applied or deleted.
    if (mounted) await _load();
  }

  Future<void> _create() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final token = await _token();
    if (!mounted) return;
    if (token == null) return _unauthorized();
    final extras =
        await loadRuleEditorExtras(context, service: _service, token: token);
    if (!mounted) return;
    final result = await showRuleEditorSheet(
      context,
      choices:
          widget.editorChoices ?? RuleEditorChoices.fromProviders(context),
      catalog: extras.catalog,
      groups: extras.groups,
      save: (body) =>
          _write((token) => _service.createRule(accessToken: token, body: body)),
    );
    if (result == null || !mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l.sprRuleSaved)));
    setState(() => _warnings = result.warnings);
    await _load();
  }

  Future<void> _manageGroups() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RuleGroupsScreen(
        service: _service,
        accessTokenLoader: widget.accessTokenLoader,
        onUnauthorized: widget.onUnauthorized,
      ),
    ));
    // Renamed or deleted groups change the sections.
    if (mounted) await _load();
  }

  // Reorder ----------------------------------------------------------------

  void _startReorder() {
    final blocks = ruleBlocks(_rules ?? const []);
    setState(() {
      _reorder = blocks;
      _reorderStart = ruleBlockIds(blocks);
    });
  }

  /// "Done": sends the new order, unless nothing moved.
  Future<void> _finishReorder() async {
    final blocks = _reorder;
    if (blocks == null) return;
    final ids = ruleBlockIds(blocks);
    if (_listEquals(ids, _reorderStart)) {
      setState(() => _reorder = null);
      return;
    }
    final l = AppLocalizations.of(context);
    setState(() => _savingOrder = true);
    final result = await _write(
        (token) => _service.reorderRules(accessToken: token, ruleIds: ids));
    if (!mounted) return;
    final rules = (result['rules'] as List?)?.cast<Rule>();
    setState(() {
      _savingOrder = false;
      _reorder = null;
      if (result['success'] == true && rules != null && rules.isNotEmpty) {
        _rules = rules;
      }
    });
    if (result['success'] != true) {
      _snack(_failureText(l, result));
      await _load();
    }
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // Apply all --------------------------------------------------------------

  /// The first call only returns what the confirmation shows (422
  /// `confirmation_required`); after the user confirms, the second call
  /// queues every rule (202).
  Future<void> _applyAll() async {
    final l = AppLocalizations.of(context);
    setState(() => _applyingAll = true);
    final first =
        await _write((token) => _service.applyAllRules(accessToken: token));
    if (!mounted) return;
    setState(() => _applyingAll = false);
    final confirmation = first['confirmation'];
    if (first['code'] != 'confirmation_required' ||
        confirmation is! RuleApplyConfirmation) {
      if (first['success'] != true) _snack(_failureText(l, first));
      return;
    }
    final confirmed = await _confirmApplyAll(confirmation);
    if (confirmed != true || !mounted) return;
    setState(() => _applyingAll = true);
    final second = await _write((token) =>
        _service.applyAllRules(accessToken: token, confirm: true));
    if (!mounted) return;
    setState(() => _applyingAll = false);
    if (second['success'] == true) {
      _snack(l.sr2ApplyAllQueued(second['ruleCount'] as int? ?? 0));
      await _load();
    } else {
      _snack(_failureText(l, second));
    }
  }

  Future<bool?> _confirmApplyAll(RuleApplyConfirmation c) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        final dl = AppLocalizations.of(context);
        final locale = Localizations.localeOf(context).toString();
        final cost = c.estimatedAiCost;
        final lines = [
          dl.sr2ApplyAllBody(c.ruleCount),
          dl.sprRuleApplyCount(c.affectedCount),
          if (c.autoCategorize)
            cost == null
                ? dl.sprRuleApplyAiNoCost
                : dl.sprRuleApplyAiCost(NumberFormat.currency(
                        locale: locale,
                        name: 'USD',
                        symbol: r'$',
                        decimalDigits: 4)
                    .format(cost)),
        ];
        return AlertDialog(
          title: Text(dl.sr2ApplyAllTitle),
          content: Text(lines.join('\n\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(dl.commonCancel),
            ),
            TextButton(
              key: const ValueKey('rulesApplyAllConfirm'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(dl.sprRuleApplyConfirm),
            ),
          ],
        );
      },
    );
  }

  // Build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final canWrite = rulesWriteEnabled(context);
    final canReorder =
        canWrite && ruleFeatureEnabled(context, ServerFeaturesProvider.rulesReorder);
    final grouped =
        ruleFeatureEnabled(context, ServerFeaturesProvider.rulesGroups);
    final canApplyAll = canWrite &&
        ruleFeatureEnabled(context, ServerFeaturesProvider.rulesApplyAll);
    final rules = _rules;
    final reorder = _reorder;
    final text = RuleText(l,
        lookup: widget.nameLookup ?? ruleNameLookupFromProviders(context));

    final List<Widget> content;
    if (rules == null && _loading) {
      content = const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else if (rules == null) {
      content = [
        _centered(SureEmptyState(
          icon: SureIcons.circleAlert,
          title: l.p3roRulesLoadFailed,
          secondaryLabel: l.commonTryAgain,
          onSecondary: _load,
        )),
      ];
    } else if (rules.isEmpty) {
      content = [
        _centered(SureEmptyState(
          icon: SureIcons.listChecks,
          title: l.p3roRulesEmpty,
          body: canWrite ? l.sprRulesEmptyBody : l.p3roRulesEmptyBody,
        )),
      ];
    } else if (reorder != null) {
      content = [_reorderList(reorder, text)];
    } else if (grouped) {
      final blocks = ruleBlocks(rules);
      final anyGroup = blocks.any((b) => b.isGroup);
      content = [
        for (final block in blocks) ...[
          if (anyGroup)
            SliverToBoxAdapter(
              child: SureSectionHeader(
                key: ValueKey('ruleSection-${block.key}'),
                label: block.isGroup
                    ? (block.groupName ?? l.sr2GroupUnnamed)
                    : l.sr2Ungrouped,
              ),
            ),
          SliverToBoxAdapter(
            child: SurePanel.rows(
              margin: EdgeInsets.fromLTRB(16, anyGroup ? 0 : 20, 16, 0),
              dividerIndent: SurePanel.iconRowDividerIndent,
              children: [for (final rule in block.rules) _ruleRow(rule, text)],
            ),
          ),
        ],
      ];
    } else {
      content = [
        SliverToBoxAdapter(
          child: SurePanel.rows(
            margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            dividerIndent: SurePanel.iconRowDividerIndent,
            children: [for (final rule in rules) _ruleRow(rule, text)],
          ),
        ),
      ];
    }

    final hasRules = rules != null && rules.isNotEmpty;
    return SureLargeTitleScaffold(
      title: l.shellRules,
      // Rules opens from Settings.
      leading: Navigator.of(context).canPop()
          ? SureBackButton(label: l.shellSettingsTitle)
          : null,
      actions: [
        if (canReorder && hasRules)
          SureNavTextButton(
            key: const ValueKey('rulesReorder'),
            label: reorder == null ? l.sr2RulesEdit : l.dsDone,
            onPressed: _savingOrder
                ? null
                : reorder == null
                    ? _startReorder
                    : _finishReorder,
          ),
        if (canWrite && reorder == null)
          SureNavIconButton(
            key: const ValueKey('rulesAdd'),
            icon: SureIcons.plus,
            semanticLabel: l.sprRuleNew,
            onPressed: rules == null ? null : _create,
          ),
      ],
      onRefresh: reorder == null ? _load : null,
      slivers: [
        for (final warning in _warnings)
          SliverToBoxAdapter(
            child: SureBanner(
              message: warning,
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            ),
          ),
        if (reorder == null)
          SliverToBoxAdapter(
            child: SurePanel.rows(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              dividerIndent: SurePanel.iconRowDividerIndent,
              children: [
                if (canApplyAll && hasRules)
                  SureListRow(
                    key: const ValueKey('rulesApplyAll'),
                    leading: SureIcon(SureIcons.repeat,
                        size: 20, color: palette.textPrimary),
                    title: l.sr2ApplyAll,
                    trailing: _applyingAll
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    onTap: _applyingAll ? null : _applyAll,
                  ),
                if (!canReorder)
                  SureListRow(
                    leading: SureIcon(SureIcons.pencil,
                        size: 20, color: palette.textPrimary),
                    title: canWrite
                        ? l.sprRulesReorderOnWeb
                        : l.p3roRulesManageOnWeb,
                    trailing: const SettingsWebMark(),
                    onTap: () => openWebFallback(context,
                        title: l.shellRules, path: RulesScreen.webPath),
                  ),
              ],
            ),
          ),
        ...content,
        if (grouped && reorder == null && rules != null)
          SliverToBoxAdapter(
            child: SurePanel.rows(
              margin: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              dividerIndent: SurePanel.iconRowDividerIndent,
              children: [
                SureListRow(
                  key: const ValueKey('rulesManageGroups'),
                  leading: SureIcon(SureIcons.shapes,
                      size: 20, color: palette.textPrimary),
                  title: l.sr2ManageGroups,
                  showChevron: true,
                  onTap: _manageGroups,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _ruleRow(Rule rule, RuleText text) {
    final l = text.l;
    final palette = SureColors.of(context).palette;
    return SureListRow(
      key: ValueKey('rule-${rule.id}'),
      title: text.title(rule),
      subtitle: [
        if (rule.actions.isNotEmpty) text.action(rule.actions.first),
        text.resourceType(rule.resourceType),
        rule.active ? l.p3roRuleActive : l.p3roRuleInactive,
      ].join(' · '),
      leading: SureIcon(
        rule.active ? SureIcons.circleCheck : SureIcons.circleDashed,
        size: 20,
        color: rule.active ? palette.success : palette.textSubdued,
        semanticLabel: rule.active ? l.p3roRuleActive : l.p3roRuleInactive,
      ),
      showChevron: true,
      onTap: () => _open(rule),
    );
  }

  /// Reorder mode: the blocks drag by their header, the rules by their
  /// handle within their block.
  Widget _reorderList(List<RuleBlock> blocks, RuleText text) {
    final l = text.l;
    final palette = SureColors.of(context).palette;
    final anyGroup = blocks.any((b) => b.isGroup);
    final canMoveBlocks = blocks.length > 1;

    Widget handle(int index, String label, {required Key key}) =>
        ReorderableDragStartListener(
          key: key,
          index: index,
          child: Semantics(
            label: label,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: SureIcon(SureIcons.gripVertical,
                  size: 20, color: palette.textSubdued),
            ),
          ),
        );

    return SliverPadding(
      padding: const EdgeInsets.only(top: 12),
      sliver: SliverReorderableList(
        itemCount: blocks.length,
        onReorderItem: (from, to) => setState(() {
          blocks.insert(to, blocks.removeAt(from));
        }),
        itemBuilder: (context, b) {
          final block = blocks[b];
          final title = block.isGroup
              ? (block.groupName ?? l.sr2GroupUnnamed)
              : l.sr2Ungrouped;
          return Material(
            key: ValueKey('reorderBlock-${block.key}'),
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (anyGroup)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: palette.textSecondary,
                            ),
                          ),
                        ),
                        if (canMoveBlocks)
                          handle(b, l.sr2MoveGroup(title),
                              key: ValueKey('reorderBlockHandle-${block.key}')),
                      ],
                    ),
                  ),
                SurePanel(
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: block.rules.length,
                    onReorderItem: (from, to) => setState(() {
                      block.rules.insert(to, block.rules.removeAt(from));
                    }),
                    itemBuilder: (context, i) {
                      final rule = block.rules[i];
                      final ruleTitle = text.title(rule);
                      return ColoredBox(
                        key: ValueKey('reorderRule-${rule.id}'),
                        color: palette.container,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (i > 0) const SureHairline(indent: 14),
                            Row(
                              children: [
                                Expanded(child: SureListRow(title: ruleTitle)),
                                handle(i, l.sr2MoveRule(ruleTitle),
                                    key: ValueKey('reorderRuleHandle-${rule.id}')),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _centered(Widget state) => SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: state),
      );
}
