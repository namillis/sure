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

/// Opens the "Spend from this goal" sheet for [goal] (feature
/// `goals.lifecycle`, action `consume`). Resolves to the updated [Goal]
/// after the spend is recorded, or null when cancelled.
Future<Goal?> showGoalConsumeSheet(
  BuildContext context, {
  required GoalsService service,
  required GoalsAuth auth,
  required Goal goal,
}) {
  return showSureSheet<Goal>(
    context: context,
    builder: (_) => GoalConsumeSheet(service: service, auth: auth, goal: goal),
  );
}

/// A large mono amount in goal currency and, when the goal has more than one
/// linked account, a "From" picker -> `POST /api/v1/goals/:id/consume`.
/// There is no outflow picker: the API has no endpoint listing them.
class GoalConsumeSheet extends StatefulWidget {
  const GoalConsumeSheet({
    super.key,
    required this.service,
    required this.auth,
    required this.goal,
  });

  final GoalsService service;
  final GoalsAuth auth;
  final Goal goal;

  @override
  State<GoalConsumeSheet> createState() => _GoalConsumeSheetState();
}

class _GoalConsumeSheetState extends State<GoalConsumeSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  String? _accountId;
  bool _saving = false;
  String? _error;

  List<GoalLinkedAccount> get _accounts => widget.goal.linkedAccounts;

  /// The picker shows only when there is a choice; with one link the server
  /// picks it from a blank id.
  bool get _picksAccount => _accounts.length > 1;

  @override
  void initState() {
    super.initState();
    if (_picksAccount) _accountId = _accounts.first.id;
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
      title: l.sg2ConsumeFrom,
      selected: _accountId ?? '',
      options: [for (final a in _accounts) (a.id, a.name)],
    );
    if (picked != null && mounted) setState(() => _accountId = picked.value);
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
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
    final result = await widget.service.consumeGoal(
      accessToken: token,
      id: widget.goal.id,
      amount: AmountParser.canonicalize(_amount.text, locale: _locale),
      accountId: _picksAccount ? _accountId : null,
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
    final account = _accounts.where((a) => a.id == _accountId).firstOrNull;

    return SureSheet(
      title: l.sg2ActionConsume,
      actionLabel: l.sg2ConsumeRecord,
      actionKey: const ValueKey('goalConsumeSave'),
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
                  key: const ValueKey('goalConsumeAmount'),
                  controller: _amount,
                  validator: _validate,
                  suffix: widget.goal.currency,
                  enabled: !_saving,
                ),
              ),
              if (_picksAccount)
                SurePanel.rows(
                  children: [
                    SureListRow(
                      key: const ValueKey('goalConsumeAccount'),
                      title: l.sg2ConsumeFrom,
                      value: account?.name,
                      showChevron: true,
                      onTap: _saving ? null : _pickAccount,
                    ),
                  ],
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Text(
                  l.sg2ConsumeHint,
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
