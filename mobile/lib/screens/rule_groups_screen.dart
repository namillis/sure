import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/rule.dart';
import '../providers/auth_provider.dart';
import '../services/rules_service.dart';
import '../theme/sure_colors.dart';
import '../widgets/ds/ds.dart';
import '../widgets/manage_widgets.dart';
import 'form_sheet_fields.dart';

/// Manage groups (Sure+ `rules.groups`): the family's rule groups from
/// `GET /api/v1/rule_groups`. "+" adds one, a tap renames it, a swipe
/// deletes it (its rules stay, without a group).
class RuleGroupsScreen extends StatefulWidget {
  const RuleGroupsScreen({
    super.key,
    this.service,
    this.accessTokenLoader,
    this.onUnauthorized,
  });

  final RulesService? service;

  /// Defaults to [AuthProvider.getValidAccessToken].
  final Future<String?> Function()? accessTokenLoader;

  /// Defaults to [AuthProvider.logout].
  final Future<void> Function()? onUnauthorized;

  @override
  State<RuleGroupsScreen> createState() => _RuleGroupsScreenState();
}

class _RuleGroupsScreenState extends State<RuleGroupsScreen> {
  late final RulesService _service;
  List<RuleGroup>? _groups;
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
    if (result['error'] == 'unauthorized') return l.manageActionFailed;
    return result['error']?.toString() ?? l.manageActionFailed;
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final token = await _token();
    if (!mounted) return;
    if (token == null) return _unauthorized();
    final result = await _service.listRuleGroups(accessToken: token);
    if (!mounted) return;
    if (result['error'] == 'unauthorized') return _unauthorized();
    final ok = result['success'] == true;
    if (!ok && _groups != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).sr2GroupsLoadFailed)));
    }
    setState(() {
      _loading = false;
      if (ok) _groups = (result['groups'] as List).cast<RuleGroup>();
    });
  }

  /// Add ([group] null) or rename a group.
  Future<void> _edit([RuleGroup? group]) async {
    final saved = await showSureSheet<RuleGroup>(
      context: context,
      builder: (_) => RuleGroupNameSheet(
        initialName: group?.name ?? '',
        isNew: group == null,
        save: (name) => _write((token) => _service.saveRuleGroup(
            accessToken: token, id: group?.id, name: name)),
      ),
    );
    if (saved != null && mounted) await _load();
  }

  Future<void> _delete(RuleGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final dl = AppLocalizations.of(context);
        final palette = SureColors.of(context).palette;
        return AlertDialog(
          title: Text(dl.sr2GroupDeleteTitle(group.name)),
          content: Text(dl.sr2GroupDeleteBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(dl.commonCancel),
            ),
            TextButton(
              key: const ValueKey('ruleGroupDeleteConfirm'),
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
    final result = await _write(
        (token) => _service.deleteRuleGroup(accessToken: token, id: group.id));
    if (!mounted) return;
    if (result['success'] == true) {
      messenger.showSnackBar(SnackBar(content: Text(l.sr2GroupDeleted)));
      await _load();
    } else {
      messenger.showSnackBar(SnackBar(content: Text(_failureText(l, result))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final groups = _groups;

    final Widget content;
    if (groups == null && _loading) {
      content = const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (groups == null) {
      content = SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: SureEmptyState(
            icon: SureIcons.circleAlert,
            title: l.sr2GroupsLoadFailed,
            secondaryLabel: l.commonTryAgain,
            onSecondary: _load,
          ),
        ),
      );
    } else if (groups.isEmpty) {
      content = SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: SureEmptyState(
            icon: SureIcons.listChecks,
            title: l.sr2GroupsEmpty,
            body: l.sr2GroupsEmptyBody,
          ),
        ),
      );
    } else {
      content = SliverToBoxAdapter(
        child: SurePanel.rows(
          margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          children: [
            for (final group in groups)
              Semantics(
                key: ValueKey('ruleGroup-${group.id}'),
                customSemanticsActions: {
                  CustomSemanticsAction(label: l.commonDelete): () =>
                      _delete(group),
                },
                child: SureSwipeActions(
                  actions: [
                    SureSwipeAction(
                      label: l.commonDelete,
                      color: palette.destructive,
                      onPressed: () => _delete(group),
                    ),
                  ],
                  child: ColoredBox(
                    color: palette.container,
                    child: SureListRow(
                      title: group.name,
                      subtitle: l.sr2GroupRuleCount(group.rulesCount),
                      showChevron: true,
                      onTap: () => _edit(group),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return SureLargeTitleScaffold(
      title: l.sr2GroupsTitle,
      leading: Navigator.of(context).canPop()
          ? SureBackButton(label: l.shellRules)
          : null,
      actions: [
        SureNavIconButton(
          key: const ValueKey('ruleGroupAdd'),
          icon: SureIcons.plus,
          semanticLabel: l.sr2GroupNew,
          onPressed: groups == null ? null : () => _edit(),
        ),
      ],
      onRefresh: _load,
      slivers: [content],
    );
  }
}

/// The New group / Rename group sheet: one Name field. [save] sends it and
/// returns the [RulesService] result; the sheet pops with the saved group.
class RuleGroupNameSheet extends StatefulWidget {
  const RuleGroupNameSheet({
    super.key,
    required this.initialName,
    required this.isNew,
    required this.save,
  });

  final String initialName;
  final bool isNew;
  final Future<Map<String, dynamic>> Function(String name) save;

  @override
  State<RuleGroupNameSheet> createState() => _RuleGroupNameSheetState();
}

class _RuleGroupNameSheetState extends State<RuleGroupNameSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initialName);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    if (_name.text.trim().isEmpty) {
      setState(() => _error = l.sr2GroupNameRequired);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await widget.save(_name.text);
    if (!mounted) return;
    if (result['success'] == true) {
      Navigator.of(context).pop(result['group'] as RuleGroup);
      return;
    }
    setState(() {
      _saving = false;
      _error = result['code'] == 'insufficient_scope'
          ? l.spmReadOnlyAccess
          : result['error'] == 'unauthorized'
              ? l.manageActionFailed
              : result['error']?.toString() ?? l.manageActionFailed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SureSheet(
      title: widget.isNew ? l.sr2GroupNew : l.sr2GroupRename,
      actionLabel: l.commonSave,
      actionKey: const ValueKey('ruleGroupSave'),
      busy: _saving,
      onAction: _save,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SurePanel.rows(
              children: [
                FormSheetFieldRow(
                  label: l.sr2GroupName,
                  controller: _name,
                  fieldKey: const ValueKey('ruleGroupName'),
                  hint: l.sr2GroupNameHint,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _save(),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              ManageErrorText(_error!),
            ],
          ],
        ),
      ),
    );
  }
}
