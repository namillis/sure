import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/rule.dart';
import '../providers/auth_provider.dart';
import '../services/rules_service.dart';
import '../theme/sure_colors.dart';
import '../utils/rule_text.dart';
import '../widgets/ds/ds.dart';
import '../widgets/open_on_web_action.dart';
import 'rule_detail_screen.dart';
import 'rule_editor_sheet.dart';
import 'settings_links.dart';

/// The family's rules from `GET /api/v1/rules`. Tap one for its conditions,
/// actions and recent runs. On a Sure+ server with `rules.write` "+" opens
/// the rule editor; elsewhere creating and editing is on the web. Reordering
/// is always on the web (the API has no ordering).
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).p3roRulesLoadFailed)));
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
    final result = await showRuleEditorSheet(
      context,
      choices:
          widget.editorChoices ?? RuleEditorChoices.fromProviders(context),
      save: (body) async {
        final token = await _token();
        if (token == null) {
          await _unauthorized();
          return {'success': false, 'error': 'unauthorized'};
        }
        final result = await _service.createRule(accessToken: token, body: body);
        if (result['error'] == 'unauthorized') await _unauthorized();
        return result;
      },
    );
    if (result == null || !mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l.sprRuleSaved)));
    setState(() => _warnings = result.warnings);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final canWrite = rulesWriteEnabled(context);
    final rules = _rules;
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
    } else {
      content = [
        SliverToBoxAdapter(
          child: SurePanel.rows(
            margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            dividerIndent: SurePanel.iconRowDividerIndent,
            children: [
              for (final rule in rules)
                SureListRow(
                  key: ValueKey('rule-${rule.id}'),
                  title: text.title(rule),
                  subtitle: [
                    if (rule.actions.isNotEmpty)
                      text.action(rule.actions.first),
                    text.resourceType(rule.resourceType),
                    rule.active ? l.p3roRuleActive : l.p3roRuleInactive,
                  ].join(' · '),
                  leading: SureIcon(
                    rule.active ? SureIcons.circleCheck : SureIcons.circleDashed,
                    size: 20,
                    color: rule.active ? palette.success : palette.textSubdued,
                    semanticLabel:
                        rule.active ? l.p3roRuleActive : l.p3roRuleInactive,
                  ),
                  showChevron: true,
                  onTap: () => _open(rule),
                ),
            ],
          ),
        ),
      ];
    }

    return SureLargeTitleScaffold(
      title: l.shellRules,
      // Rules opens from Settings.
      leading: Navigator.of(context).canPop()
          ? SureBackButton(label: l.shellSettingsTitle)
          : null,
      actions: [
        if (canWrite)
          SureNavIconButton(
            key: const ValueKey('rulesAdd'),
            icon: SureIcons.plus,
            semanticLabel: l.sprRuleNew,
            onPressed: rules == null ? null : _create,
          ),
      ],
      onRefresh: _load,
      slivers: [
        for (final warning in _warnings)
          SliverToBoxAdapter(
            child: SureBanner(
              message: warning,
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            ),
          ),
        SliverToBoxAdapter(
          child: SurePanel.rows(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            dividerIndent: SurePanel.iconRowDividerIndent,
            children: [
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
      ],
    );
  }

  Widget _centered(Widget state) => SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: state),
      );
}
