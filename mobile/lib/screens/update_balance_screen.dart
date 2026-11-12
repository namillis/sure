import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../providers/auth_provider.dart';
import '../providers/privacy_provider.dart';
import '../services/valuations_service.dart';
import '../theme/sure_colors.dart';
import '../utils/amount_parser.dart';
import '../utils/money_masker.dart';
import '../widgets/ds/ds.dart';
import '../widgets/form_error_text.dart';
import 'form_sheet_fields.dart';

/// Opens [UpdateBalanceScreen] as a Sure sheet. Resolves `true` once the
/// server accepted the new balance; otherwise null.
Future<bool?> showUpdateBalanceSheet(
  BuildContext context, {
  required Account account,
  ValuationsService? valuationsService,
}) {
  return showSureSheet<bool>(
    context: context,
    builder: (_) => UpdateBalanceScreen(
      account: account,
      valuationsService: valuationsService,
    ),
  );
}

/// Sets an account's balance on a date (a valuation), as sheet content:
/// "Cancel · Update balance · Save", a large new-balance field, the current
/// balance under it, then the As of date and an optional note. Pops `true`
/// once the server accepted it. Open it with [showUpdateBalanceSheet].
class UpdateBalanceScreen extends StatefulWidget {
  const UpdateBalanceScreen({
    super.key,
    required this.account,
    this.valuationsService,
  });

  final Account account;
  final ValuationsService? valuationsService;

  @override
  State<UpdateBalanceScreen> createState() => _UpdateBalanceScreenState();
}

class _UpdateBalanceScreenState extends State<UpdateBalanceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _balanceController = TextEditingController();
  final _noteController = TextEditingController();
  late final ValuationsService _service =
      widget.valuationsService ?? ValuationsService();
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _balanceController.dispose();
    _noteController.dispose();
    if (widget.valuationsService == null) _service.close();
    super.dispose();
  }

  String get _locale => Localizations.localeOf(context).toString();

  String? _validateBalance(String? value) {
    final l = AppLocalizations.of(context);
    if (value == null || value.trim().isEmpty) {
      return l.accountActionsBalanceRequired;
    }
    try {
      AmountParser.parse(value, locale: _locale);
    } on FormatException {
      return l.accountActionsInvalidNumber;
    }
    return null;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final authProvider = context.read<AuthProvider>();

    setState(() {
      _submitting = true;
      _error = null;
    });

    final token = await authProvider.getValidAccessToken();
    if (!mounted) return;
    if (token == null) {
      await authProvider.logout();
      return;
    }

    final result = await _service.createValuation(
      accessToken: token,
      accountId: widget.account.id,
      amount: AmountParser.canonicalize(_balanceController.text, locale: _locale),
      date: DateFormat('yyyy-MM-dd').format(_date),
      notes: _noteController.text,
    );
    if (!mounted) return;

    if (result['error'] == 'unauthorized') {
      await authProvider.logout();
      return;
    }
    if (result['success'] == true) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.accountActionsBalanceUpdated)),
      );
      navigator.pop(true);
      return;
    }
    setState(() {
      _submitting = false;
      _error = result['error']?.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final hidden = context.watch<PrivacyProvider>().hidden;

    return SureSheet(
      title: l.accountActionsUpdateBalance,
      actionLabel: l.accountActionsSave,
      actionKey: const ValueKey('updateBalanceSave'),
      onAction: _submit,
      busy: _submitting,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.account.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
              const SizedBox(height: 4),
              FormSheetAmountField(
                key: const ValueKey('updateBalanceAmount'),
                controller: _balanceController,
                validator: _validateBalance,
                suffix: widget.account.currency,
                signed: true,
              ),
              const SizedBox(height: 4),
              Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: _WasBalance(
                    template: l.ds3fWasBalance,
                    amount:
                        MoneyMasker.mask(widget.account.balance, hidden: hidden),
                    color: palette.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SurePanel.rows(
                children: [
                  SureListRow(
                    key: const ValueKey('updateBalanceDate'),
                    title: l.ds3fAsOf,
                    value: SureDates.relativeDayOf(context, _date),
                    showChevron: true,
                    onTap: _submitting ? null : _pickDate,
                  ),
                  FormSheetFieldRow(
                    fieldKey: const ValueKey('updateBalanceNote'),
                    label: l.ds3fNote,
                    controller: _noteController,
                    hint: l.ds3fOptional,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.newline,
                    keyboardType: TextInputType.multiline,
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                FormErrorText(_error!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "Was $9,412.50": the localized sentence with only the amount in mono.
class _WasBalance extends StatelessWidget {
  const _WasBalance({
    required this.template,
    required this.amount,
    required this.color,
  });

  final String Function(String amount) template;
  final String amount;
  final Color color;

  static const _marker = '\u0000';

  @override
  Widget build(BuildContext context) {
    final parts = template(_marker).split(_marker);
    final style = TextStyle(fontSize: 13, color: color);
    return Text.rich(
      key: const ValueKey('updateBalanceWas'),
      TextSpan(
        style: style,
        children: [
          TextSpan(text: parts.first),
          TextSpan(text: amount, style: SureMoney.tabular(style)),
          if (parts.length > 1) TextSpan(text: parts.sublist(1).join()),
        ],
      ),
      maxLines: 1,
      textAlign: TextAlign.center,
    );
  }
}
