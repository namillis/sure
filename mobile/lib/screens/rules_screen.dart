import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/rule.dart';
import '../providers/auth_provider.dart';
import '../services/rules_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../utils/rule_text.dart';
import '../widgets/manage_widgets.dart';
import '../widgets/open_on_web_action.dart';
import '../widgets/sure_list_group.dart';
import 'rule_detail_screen.dart';

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

    final Widget content;
    if (rules == null && _loading) {
      content = const Padding(
        padding: EdgeInsets.only(top: 96),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (rules == null) {
      content = ManageMessage(
        icon: Icons.error_outline,
        title: l.p3roRulesLoadFailed,
        onRetry: _load,
      );
    } else if (rules.isEmpty) {
      content = ManageMessage(
        icon: Icons.rule,
        title: l.p3roRulesEmpty,
        body: l.p3roRulesEmptyBody,
      );
    } else {
      content = SureListGroup(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        children: [
          for (final rule in rules)
            SureListRow(
              title: text.title(rule),
              subtitle: [
                if (rule.actions.isNotEmpty) text.action(rule.actions.first),
                text.resourceType(rule.resourceType),
                rule.active ? l.p3roRuleActive : l.p3roRuleInactive,
              ].join(' · '),
              leading: Icon(
                rule.active ? Icons.check_circle : Icons.pause_circle_outline,
                color: rule.active ? palette.success : palette.textSubdued,
                semanticLabel:
                    rule.active ? l.p3roRuleActive : l.p3roRuleInactive,
              ),
              showChevron: true,
              onTap: () => _open(rule),
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.shellRules)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: SureSpacing.huge),
          children: [
            SureListGroup(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              children: [
                SureListRow(
                  leading: Icon(Icons.edit_note, color: palette.textPrimary),
                  title: l.p3roRulesManageOnWeb,
                  trailing: Icon(
                    Icons.language,
                    size: 18,
                    color: palette.textSubdued,
                    semanticLabel: l.shellOpensOnWeb,
                  ),
                  onTap: () => openWebFallback(context,
                      title: l.shellRules, path: RulesScreen.webPath),
                ),
              ],
            ),
            content,
          ],
        ),
      ),
    );
  }
}
