import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../models/recurring_transaction.dart';
import '../services/recurring_transactions_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../utils/amount_parser.dart';
import '../utils/recurring_grouping.dart';
import '../widgets/ds/ds.dart';
import '../widgets/sure_text_field.dart';
import 'recurring_screen.dart' show confirmRecurringDelete;

/// Starting values for a new recurring transaction, e.g. one made from a
/// transaction ("Mark as recurring").
class RecurringPrefill {
  const RecurringPrefill({
    required this.name,
    required this.amount,
    this.currency,
    required this.lastOccurrenceDate,
    required this.nextExpectedDate,
    required this.expectedDayOfMonth,
    this.income = false,
    this.accountId,
    this.merchantId,
  });

  final String name;

  /// Unsigned, in major units; [income] gives the direction.
  final double amount;
  final bool income;

  /// Null keeps the form's default (the first account's currency).
  final String? currency;
  final String? accountId;
  final String? merchantId;
  final DateTime lastOccurrenceDate;
  final DateTime nextExpectedDate;

  /// Sent as `expected_day_of_month` unless the next date is changed, so a
  /// series from the 31st keeps the 31st after a short month.
  final int expectedDayOfMonth;
}

/// Adds a recurring transaction, or edits [existing]. Pops `true` after a
/// save or delete so the list reloads.
///
/// The API creates with name, amount, currency, account and dates, but
/// updates only status, dates, autopay, payment link and notes, and cannot
/// set a cadence (new items are monthly on the next date's day). Locked
/// fields show read-only in edit mode.
class RecurringFormScreen extends StatefulWidget {
  const RecurringFormScreen({
    super.key,
    this.existing,
    this.prefill,
    this.onCreated,
    required this.accounts,
    required this.service,
    required this.accessTokenLoader,
    required this.onUnauthorized,
    this.clock,
  });

  final RecurringTransaction? existing;

  /// Starting values for a new item; ignored with [existing].
  final RecurringPrefill? prefill;

  /// Called with the created item after a successful create, before the
  /// sheet pops `true`.
  final ValueChanged<RecurringTransaction>? onCreated;
  final List<Account> accounts;
  final RecurringTransactionsService service;
  final Future<String?> Function() accessTokenLoader;
  final Future<void> Function() onUnauthorized;
  final DateTime Function()? clock;

  @override
  State<RecurringFormScreen> createState() => _RecurringFormScreenState();
}

class _RecurringFormScreenState extends State<RecurringFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _currency;
  late final TextEditingController _paymentUrl;
  late final TextEditingController _notes;
  late bool _income;
  late bool _active;
  late bool _autopay;
  String? _accountId;
  String? _merchantId;
  int? _expectedDay;
  late DateTime _nextDate;
  late DateTime _lastDate;
  bool _saving = false;
  String? _serverError;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final p = e == null ? widget.prefill : null;
    final today = (widget.clock ?? DateTime.now)();
    final todayDate = DateTime(today.year, today.month, today.day);
    _name = TextEditingController(text: e?.displayName ?? p?.name ?? '');
    _amount = TextEditingController(
      text: e != null
          ? RecurringGrouping.amountOf(e).abs().toStringAsFixed(2)
          : p != null
              ? p.amount.abs().toStringAsFixed(2)
              : '',
    );
    _accountId = e?.accountId ?? p?.accountId;
    _merchantId = p?.merchantId;
    _expectedDay = p?.expectedDayOfMonth;
    _currency = TextEditingController(
      text: e?.currency ??
          p?.currency ??
          (widget.accounts.isNotEmpty ? widget.accounts.first.currency : 'USD'),
    );
    _paymentUrl = TextEditingController(text: e?.paymentUrl ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _income = e?.isInflow ?? p?.income ?? false;
    _active = e == null || e.isActive;
    _autopay = e?.autopay ?? false;
    _nextDate = e?.nextExpectedDate ?? p?.nextExpectedDate ?? todayDate;
    _lastDate = e?.lastOccurrenceDate ??
        p?.lastOccurrenceDate ??
        DateTime(_nextDate.year, _nextDate.month - 1, _nextDate.day);
  }

  @override
  void dispose() {
    for (final c in [_name, _amount, _currency, _paymentUrl, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _locale => Localizations.localeOf(context).toString();

  double? _parsedAmount() {
    try {
      return AmountParser.parse(_amount.text, locale: _locale).value.abs();
    } on FormatException {
      return null;
    }
  }

  Future<void> _pickDate({required bool next}) async {
    final initial = next ? _nextDate : _lastDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (next) {
        _nextDate = picked;
        _expectedDay = null;
      } else {
        _lastDate = picked;
      }
    });
    _formKey.currentState?.validate();
  }

  static String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Map<String, dynamic> _attributes() {
    final url = _paymentUrl.text.trim();
    final notes = _notes.text.trim();
    final common = <String, dynamic>{
      'status': _active ? 'active' : 'inactive',
      'next_expected_date': _iso(_nextDate),
      'expected_day_of_month': _expectedDay ?? _nextDate.day,
      'autopay': _autopay,
      'payment_url': url.isEmpty ? null : url,
      'notes': notes.isEmpty ? null : notes,
    };
    if (_editing) return common;
    final amount = _parsedAmount()!;
    return {
      'name': _name.text.trim(),
      // Sure's sign convention: positive is money out.
      'amount': _income ? -amount : amount,
      'currency': _currency.text.trim().toUpperCase(),
      if (_accountId != null) 'account_id': _accountId,
      if (_merchantId != null) 'merchant_id': _merchantId,
      'last_occurrence_date': _iso(_lastDate),
      ...common,
    };
  }

  Future<void> _save() async {
    setState(() => _serverError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final token = await widget.accessTokenLoader();
    if (!mounted) return;
    if (token == null) return widget.onUnauthorized();
    final result = _editing
        ? await widget.service.update(
            accessToken: token,
            id: widget.existing!.id,
            attributes: _attributes(),
          )
        : await widget.service.create(
            accessToken: token,
            attributes: _attributes(),
          );
    if (!mounted) return;
    if (result['error'] == 'unauthorized') return widget.onUnauthorized();
    if (result['success'] == true) {
      final created = result['recurring_transaction'];
      if (!_editing && created is RecurringTransaction) {
        widget.onCreated?.call(created);
      }
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _serverError = result['error']?.toString() ??
          AppLocalizations.of(context).recurringSaveFailed;
    });
  }

  Future<void> _delete() async {
    final item = widget.existing!;
    if (!await confirmRecurringDelete(context, item) || !mounted) return;
    setState(() => _saving = true);
    final token = await widget.accessTokenLoader();
    if (!mounted) return;
    if (token == null) return widget.onUnauthorized();
    final result = await widget.service.delete(accessToken: token, id: item.id);
    if (!mounted) return;
    if (result['error'] == 'unauthorized') return widget.onUnauthorized();
    if (result['success'] == true) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _serverError = AppLocalizations.of(context).recurringActionFailed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = SureColors.of(context).palette;
    final dateFormat = DateFormat.yMMMd(_locale);
    final locked = _editing;
    const gap = SizedBox(height: SureSpacing.xl);

    final accountIds = widget.accounts.map((a) => a.id).toSet();
    final accountValue = accountIds.contains(_accountId) ? _accountId : null;

    return SureSheet(
      title: _editing ? l.recurringEditTitle : l.recurringNewTitle,
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
                locked ? l.recurringLockedNote : l.recurringCadenceNote,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: palette.textSecondary),
              ),
              gap,
              if (!locked) ...[
                SureSegmentedControl<bool>(
                  segments: [
                    SureSegment(value: false, label: l.recurringExpense),
                    SureSegment(value: true, label: l.recurringIncome),
                  ],
                  selected: _income,
                  onChanged: (v) => setState(() => _income = v),
                ),
                gap,
              ],
              SureTextField(
                controller: _name,
                label: l.recurringFieldName,
                readOnly: locked,
                enabled: !locked,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                validator: locked
                    ? null
                    : (v) => (v == null || v.trim().isEmpty)
                        ? l.recurringErrorNameRequired
                        : null,
              ),
              gap,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: SureTextField(
                      controller: _amount,
                      label: l.recurringFieldAmount,
                      readOnly: locked,
                      enabled: !locked,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: locked
                          ? null
                          : (_) {
                              final amount = _parsedAmount();
                              return amount == null || amount <= 0
                                  ? l.recurringErrorAmountInvalid
                                  : null;
                            },
                    ),
                  ),
                  const SizedBox(width: SureSpacing.lg),
                  Expanded(
                    child: SureTextField(
                      controller: _currency,
                      label: l.recurringFieldCurrency,
                      readOnly: locked,
                      enabled: !locked,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 3,
                      validator: locked
                          ? null
                          : (v) =>
                              RegExp(r'^[A-Za-z]{3}$').hasMatch(v?.trim() ?? '')
                                  ? null
                                  : l.recurringErrorCurrencyInvalid,
                    ),
                  ),
                ],
              ),
              gap,
              if (locked)
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: l.recurringFieldAccount,
                    enabled: false,
                  ),
                  child: Text(
                      widget.existing!.accountName ?? l.recurringNoAccount),
                )
              else if (widget.accounts.isNotEmpty)
                DropdownButtonFormField<String?>(
                  initialValue: accountValue,
                  isExpanded: true,
                  decoration:
                      InputDecoration(labelText: l.recurringFieldAccount),
                  items: [
                    DropdownMenuItem(
                        value: null, child: Text(l.recurringNoAccount)),
                    for (final a in widget.accounts)
                      DropdownMenuItem(
                        value: a.id,
                        child: Text(a.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (id) => setState(() {
                    _accountId = id;
                    final account =
                        widget.accounts.where((a) => a.id == id).firstOrNull;
                    if (account != null) _currency.text = account.currency;
                  }),
                ),
              gap,
              _DateField(
                key: const ValueKey('recurring-next-date'),
                label: l.recurringFieldNextDate,
                text: dateFormat.format(_nextDate),
                onTap: () => _pickDate(next: true),
              ),
              gap,
              _DateField(
                key: const ValueKey('recurring-last-date'),
                label: l.recurringFieldLastDate,
                text: dateFormat.format(_lastDate),
                onTap: locked ? null : () => _pickDate(next: false),
                validator: locked
                    ? null
                    : (_) => _lastDate.isBefore(_nextDate)
                        ? null
                        : l.recurringErrorLastAfterNext,
              ),
              const SizedBox(height: SureSpacing.md),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(l.recurringFieldActive),
                subtitle: Text(l.recurringFieldActiveHint),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(l.recurringFieldAutopay),
                value: _autopay,
                onChanged: (v) => setState(() => _autopay = v),
              ),
              const SizedBox(height: SureSpacing.md),
              SureTextField(
                controller: _paymentUrl,
                label: l.recurringFieldPaymentUrl,
                hint: 'https://',
                keyboardType: TextInputType.url,
                validator: (v) {
                  final url = v?.trim() ?? '';
                  if (url.isEmpty) return null;
                  final uri = Uri.tryParse(url);
                  final ok = uri != null &&
                      (uri.scheme == 'http' || uri.scheme == 'https') &&
                      uri.host.isNotEmpty;
                  return ok ? null : l.recurringErrorUrlInvalid;
                },
              ),
              gap,
              SureTextField(
                controller: _notes,
                label: l.recurringFieldNotes,
                maxLines: 3,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
              ),
              if (_serverError != null) ...[
                gap,
                Text(
                  _serverError!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: palette.destructive),
                ),
              ],
              if (_editing) ...[
                const SizedBox(height: SureSpacing.xxxl),
                SureButtonPanel(
                  label: l.commonDelete,
                  destructive: true,
                  onPressed: _saving ? null : _delete,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A read-only field that opens a date picker; disabled when [onTap] is
/// null.
class _DateField extends StatefulWidget {
  const _DateField({
    super.key,
    required this.label,
    required this.text,
    this.onTap,
    this.validator,
  });

  final String label;
  final String text;
  final VoidCallback? onTap;
  final FormFieldValidator<String>? validator;

  @override
  State<_DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<_DateField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.text);

  @override
  void didUpdateWidget(_DateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _controller.text = widget.text;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SureTextField(
      controller: _controller,
      label: widget.label,
      readOnly: true,
      enabled: widget.onTap != null,
      onTap: widget.onTap,
      suffixIcon: const Padding(
        padding: EdgeInsets.all(12),
        child: SureIcon(SureIcons.calendar, size: 18),
      ),
      validator: widget.validator,
    );
  }
}
