import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/goal.dart';
import '../services/goals_service.dart';
import '../theme/sure_colors.dart';
import '../utils/amount_parser.dart';
import '../widgets/ds/ds.dart';
import '../widgets/manage_widgets.dart';
import 'form_sheet_fields.dart';
import 'goals_screen.dart';

/// Opens the "I saved toward this" sheet for [goal] (feature
/// `goals.pledges`). Resolves to the refreshed [Goal] after the pledge is
/// recorded, or null when cancelled.
Future<Goal?> showPledgeSheet(
  BuildContext context, {
  required GoalsService service,
  required GoalsAuth auth,
  required Goal goal,
}) {
  return showSureSheet<Goal>(
    context: context,
    builder: (_) => PledgeSheet(service: service, auth: auth, goal: goal),
  );
}

/// A large mono amount and a "From" account limited to the goal's linked
/// accounts -> `POST /api/v1/goals/:id/pledges`.
class PledgeSheet extends StatefulWidget {
  const PledgeSheet({
    super.key,
    required this.service,
    required this.auth,
    required this.goal,
  });

  final GoalsService service;
  final GoalsAuth auth;
  final Goal goal;

  @override
  State<PledgeSheet> createState() => _PledgeSheetState();
}

class _PledgeSheetState extends State<PledgeSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  String? _accountId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final accounts = widget.goal.linkedAccounts;
    if (accounts.isNotEmpty) _accountId = accounts.first.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  String get _locale => Localizations.localeOf(context).toString();

  String? _validate(String? value) {
    final l = AppLocalizations.of(context);
    try {
      if (AmountParser.parse(value ?? '', locale: _locale).value <= 0) {
        return l.spgTargetInvalid;
      }
    } on FormatException {
      return l.spgTargetInvalid;
    }
    return null;
  }

  Future<void> _pickAccount() async {
    final l = AppLocalizations.of(context);
    final picked = await showManageOptionSheet<String>(
      context,
      title: l.spgPledgeFrom,
      selected: _accountId ?? '',
      options: [
        for (final a in widget.goal.linkedAccounts) (a.id, a.name),
      ],
    );
    if (picked != null && mounted) setState(() => _accountId = picked.value);
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final accountId = _accountId;
    if (!_formKey.currentState!.validate() || accountId == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final token = await widget.auth.token(context);
    if (!mounted) return;
    if (token == null) {
      navigator.pop();
      return widget.auth.unauthorized(context);
    }
    final result = await widget.service.createPledge(
      accessToken: token,
      goalId: widget.goal.id,
      amount: AmountParser.canonicalize(_amount.text, locale: _locale),
      accountId: accountId,
    );
    if (!mounted) return;
    if (result['error'] == 'unauthorized') {
      navigator.pop();
      return widget.auth.unauthorized(context);
    }
    if (result['success'] != true) {
      setState(() {
        _saving = false;
        _error = goalsErrorText(l, result);
      });
      return;
    }
    navigator.pop(result['goal'] as Goal);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final accounts = widget.goal.linkedAccounts;
    final account = accounts.where((a) => a.id == _accountId).firstOrNull;

    return SureSheet(
      title: l.spgSavedToward,
      actionLabel: l.spgPledgeRecord,
      actionKey: const ValueKey('pledgeSave'),
      onAction: _save,
      busy: _saving,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.goal.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: FormSheetAmountField(
                  key: const ValueKey('pledgeAmount'),
                  controller: _amount,
                  validator: _validate,
                  suffix: widget.goal.currency,
                  enabled: !_saving,
                ),
              ),
              SurePanel.rows(
                children: [
                  SureListRow(
                    key: const ValueKey('pledgeAccount'),
                    title: l.spgPledgeFrom,
                    value: account?.name,
                    showChevron: accounts.length > 1,
                    onTap: accounts.length > 1 && !_saving
                        ? _pickAccount
                        : null,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Text(
                  l.spgPledgeHint,
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                  child: ManageErrorText(_error!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
