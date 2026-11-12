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
import 'settings_links.dart';

/// The family's rules from `GET /api/v1/rules`, read-only. Tap one for its
/// conditions, actions and recent runs; creating and editing is on the web.
class RulesScreen extends StatefulWidget {
  const RulesScreen({
    super.key,
    this.service,
    this.accessTokenLoader,
    this.onUnauthorized,
    this.nameLookup,
  });

  final RulesService? service;

  /// Defaults to [AuthProvider.getValidAccessToken].
  final Future<String?> Function()? accessTokenLoader;

  /// Defaults to [AuthProvider.logout].
  final Future<void> Function()? onUnauthorized;

  /// Names for category, tag, merchant and account ids; defaults to the
  /// app's providers (see [ruleNameLookupFromProviders]).
  final RuleNameLookup? nameLookup;

  static const webPath = '/rules';

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  late final RulesService _service;
  List<Rule>? _rules;
  bool _loading = true;

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

  void _open(Rule rule) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RuleDetailScreen(
        ruleId: rule.id,
        initialRule: rule,
        service: _service,
        accessTokenLoader: widget.accessTokenLoader,
        onUnauthorized: widget.onUnauthorized,
        nameLookup: widget.nameLookup,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
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
          body: l.p3roRulesEmptyBody,
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
      onRefresh: _load,
      slivers: [
        SliverToBoxAdapter(
          child: SurePanel.rows(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            dividerIndent: SurePanel.iconRowDividerIndent,
            children: [
              SureListRow(
                leading: SureIcon(SureIcons.pencil,
                    size: 20, color: palette.textPrimary),
                title: l.p3roRulesManageOnWeb,
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
