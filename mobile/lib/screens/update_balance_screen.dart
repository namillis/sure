import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../providers/auth_provider.dart';
import '../providers/privacy_provider.dart';
import '../services/valuations_service.dart';
import '../utils/amount_parser.dart';
import '../utils/money_masker.dart';
import '../widgets/form_error_text.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_text_field.dart';

/// Sets an account's balance on a date (a valuation). Pops `true` once the
/// server accepted it.
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
  final _dateController = TextEditingController();
  late final ValuationsService _service =
      widget.valuationsService ?? ValuationsService();
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  bool _submitting = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dateController.text = DateFormat.yMMMd(_locale).format(_date);
  }

  @override
  void dispose() {
    _balanceController.dispose();
    _noteController.dispose();
    _dateController.dispose();
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
    setState(() {
      _date = picked;
      _dateController.text = DateFormat.yMMMd(_locale).format(picked);
    });
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
    final hidden = context.watch<PrivacyProvider>().hidden;

    return Scaffold(
      appBar: AppBar(title: Text(l.accountActionsUpdateBalance)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(widget.account.name,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                l.accountActionsCurrentBalance(
                  MoneyMasker.mask(widget.account.balance, hidden: hidden),
                ),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
              SureTextField(
                key: const ValueKey('updateBalanceAmount'),
                controller: _balanceController,
                label: l.accountActionsNewBalance,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                suffixIcon: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(widget.account.currency),
                ),
                validator: _validateBalance,
                autofocus: true,
              ),
              const SizedBox(height: 16),
              SureTextField(
                controller: _dateController,
                label: l.accountActionsDate,
                readOnly: true,
                prefixIcon: const Icon(Icons.calendar_today),
                onTap: _pickDate,
              ),
              const SizedBox(height: 16),
              SureTextField(
                controller: _noteController,
                label: l.accountActionsNote,
                maxLines: 3,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                FormErrorText(_error!),
              ],
              const SizedBox(height: 24),
              SureButton(
                label: l.accountActionsSave,
                onPressed: _submitting ? null : _submit,
                loading: _submitting,
                fullWidth: true,
                size: SureButtonSize.lg,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
