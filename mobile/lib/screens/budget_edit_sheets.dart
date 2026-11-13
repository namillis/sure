import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/budget.dart';
import '../providers/budgets_provider.dart';
import '../providers/privacy_provider.dart';
import '../theme/sure_colors.dart';
import '../utils/amount_parser.dart';
import '../utils/money_masker.dart';
import '../utils/split_math.dart';
import '../widgets/ds/ds.dart';
import '../widgets/form_error_text.dart';
import 'form_sheet_fields.dart';

/// The Sure+ (`budgets.write`) edit sheets of the Budget screen: one category
/// line ([showBudgetCategorySheet]) and the month's totals
/// ([showBudgetTotalsSheet]). Both save through [BudgetsProvider], which
/// reloads the month on success and remembers a budget the server refused as
/// shared read-only.

/// Opens the sheet for [budgetCategory]: its limit as a large amount, what was
/// spent, the rollover switch and a row to its transactions. Resolves `true`
/// once saved.
Future<bool?> showBudgetCategorySheet(
  BuildContext context, {
  required BudgetsProvider provider,
  required Budget budget,
  required BudgetCategory budgetCategory,
  required Future<String?> Function() accessToken,
  required VoidCallback onOpenTransactions,
  required VoidCallback onUnauthorized,
}) {
  return showSureSheet<bool>(
    context: context,
    builder: (_) => BudgetCategorySheet(
      provider: provider,
      budget: budget,
      budgetCategory: budgetCategory,
      accessToken: accessToken,
      onOpenTransactions: onOpenTransactions,
      onUnauthorized: onUnauthorized,
    ),
  );
}

/// Opens the sheet for [budget]'s total budget and expected income. Resolves
/// `true` once saved.
Future<bool?> showBudgetTotalsSheet(
  BuildContext context, {
  required BudgetsProvider provider,
  required Budget budget,
  required Future<String?> Function() accessToken,
  required VoidCallback onUnauthorized,
}) {
  return showSureSheet<bool>(
    context: context,
    builder: (_) => BudgetTotalsSheet(
      provider: provider,
      budget: budget,
      accessToken: accessToken,
      onUnauthorized: onUnauthorized,
    ),
  );
}

/// [minorUnits] of [currency] as editable text in [locale] ("650.00",
/// "650,00"); empty for null or zero so the field shows its placeholder.
String budgetEditText(int? minorUnits, String currency, String locale) {
  if (minorUnits == null || minorUnits == 0) return '';
  final digits = _currencyDigits(currency);
  final units =
      minorUnits * math.pow(10, SplitMath.scale - digits).toInt();
  return SplitMath.toEditText(units, locale: locale, minFractionDigits: digits);
}

int _currencyDigits(String currency) {
  try {
    final digits = NumberFormat.simpleCurrency(name: currency).decimalDigits;
    return (digits ?? 2).clamp(0, SplitMath.scale);
  } catch (_) {
    return 2;
  }
}

/// The amount in [text] as the API's decimal string, `"0"` when empty, or
/// null when it isn't a number of 0 or more.
String? _canonicalAmount(String text, String locale) {
  if (text.trim().isEmpty) return '0';
  try {
    final parsed = AmountParser.parse(text, locale: locale);
    return parsed.value < 0 ? null : parsed.canonicalValue;
  } on FormatException {
    return null;
  }
}

/// What a failed save shows. Null for a read-only refusal, which the sheet
/// shows as its own state, and for a 401, which closes the sheet.
String? _saveError(AppLocalizations l, Map<String, dynamic> result) {
  switch (result['code']) {
    case 'insufficient_scope':
      return l.spmReadOnlyAccess;
    case 'forbidden':
      return null;
    case 'validation_failed':
      return result['error']?.toString() ?? l.spbSaveFailed;
  }
  return l.spbSaveFailed;
}

class BudgetCategorySheet extends StatefulWidget {
  const BudgetCategorySheet({
    super.key,
    required this.provider,
    required this.budget,
    required this.budgetCategory,
    required this.accessToken,
    required this.onOpenTransactions,
    required this.onUnauthorized,
  });

  final BudgetsProvider provider;
  final Budget budget;
  final BudgetCategory budgetCategory;
  final Future<String?> Function() accessToken;
  final VoidCallback onOpenTransactions;
  final VoidCallback onUnauthorized;

  @override
  State<BudgetCategorySheet> createState() => _BudgetCategorySheetState();
}

class _BudgetCategorySheetState extends State<BudgetCategorySheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  late bool _rollover = widget.budgetCategory.rolloverEnabled;
  late bool _readOnly = widget.provider.isReadOnly;
  bool _prefilled = false;
  String _initialText = '';
  bool _busy = false;
  String? _error;

  String get _locale => Localizations.localeOf(context).toString();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    final bc = widget.budgetCategory;
    _amount.text = _initialText =
        budgetEditText(bc.budgetedSpendingCents, bc.currency, _locale);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    if (_canonicalAmount(value ?? '', _locale) == null) {
      return AppLocalizations.of(context).spbInvalidAmount;
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final l = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final bc = widget.budgetCategory;
    final amountChanged = _amount.text != _initialText;
    final rolloverChanged = _rollover != bc.rolloverEnabled;
    if (!amountChanged && !rolloverChanged) {
      navigator.pop();
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final token = await widget.accessToken();
    if (!mounted) return;
    if (token == null) {
      navigator.pop();
      widget.onUnauthorized();
      return;
    }
    final result = await widget.provider.updateBudgetCategory(
      accessToken: token,
      budgetCategory: bc,
      budgetedSpending:
          amountChanged ? _canonicalAmount(_amount.text, _locale) : null,
      rolloverEnabled: rolloverChanged ? _rollover : null,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      messenger.showSnackBar(SnackBar(content: Text(l.spbSaved)));
      navigator.pop(true);
      return;
    }
    if (result['error'] == 'unauthorized') {
      navigator.pop();
      widget.onUnauthorized();
      return;
    }
    setState(() {
      _busy = false;
      _readOnly = _readOnly || result['code'] == 'forbidden';
      _error = _saveError(l, result);
    });
  }

  void _openTransactions() {
    Navigator.of(context).pop();
    widget.onOpenTransactions();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final hidden = context.watch<PrivacyProvider>().hidden;
    final bc = widget.budgetCategory;
    final spent = MoneyMasker.mask(bc.actualSpending ?? '--', hidden: hidden);

    return SureSheet(
      title: bc.name,
      actionKey: const ValueKey('budgetCategorySave'),
      onAction: _save,
      actionEnabled: !_readOnly,
      busy: _busy,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormSheetAmountField(
                key: const ValueKey('budgetCategoryAmount'),
                controller: _amount,
                validator: _validate,
                enabled: !_readOnly && !_busy,
                autofocus: !_readOnly,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                FormErrorText(_error!),
              ],
              if (bc.hasDerivedAmounts) ...[
                const SizedBox(height: 4),
                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _AmountSentence(
                      key: const ValueKey('budgetCategorySpent'),
                      parts: [
                        (
                          widget.budget.current
                              ? l.spbSpentThisMonth
                              : l.spbSpentInPeriod,
                          spent,
                        ),
                        // Sure+ `budgets.permissions`: the web's "/m avg".
                        if ((bc.medianSpentCents ?? 0) != 0 &&
                            bc.medianSpent != null)
                          (
                            l.sb2AvgSuffix,
                            MoneyMasker.mask(bc.medianSpent!, hidden: hidden),
                          ),
                      ],
                      color: palette.textSecondary,
                    ),
                  ),
                ),
              ],
              if (_readOnly) ...[
                const SizedBox(height: 16),
                SureBanner(
                  icon: SureIcons.info,
                  message: l.spbSharedReadOnly,
                  margin: EdgeInsets.zero,
                ),
              ],
              const SizedBox(height: 20),
              SurePanel.rows(
                children: [
                  if (bc.hasRolloverSetting)
                    SureListRow(
                      key: const ValueKey('budgetCategoryRollover'),
                      title: l.spbRollover,
                      enabled: !_readOnly,
                      trailing: Switch.adaptive(
                        value: _rollover,
                        onChanged: _readOnly || _busy
                            ? null
                            : (value) => setState(() => _rollover = value),
                        activeTrackColor: palette.success,
                      ),
                    ),
                  SureListRow(
                    key: const ValueKey('budgetCategoryTransactions'),
                    title: l.spbTransactions,
                    showChevron: true,
                    onTap: _openTransactions,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BudgetTotalsSheet extends StatefulWidget {
  const BudgetTotalsSheet({
    super.key,
    required this.provider,
    required this.budget,
    required this.accessToken,
    required this.onUnauthorized,
  });

  final BudgetsProvider provider;
  final Budget budget;
  final Future<String?> Function() accessToken;
  final VoidCallback onUnauthorized;

  @override
  State<BudgetTotalsSheet> createState() => _BudgetTotalsSheetState();
}

class _BudgetTotalsSheetState extends State<BudgetTotalsSheet> {
  final _formKey = GlobalKey<FormState>();
  final _spending = TextEditingController();
  final _income = TextEditingController();
  late bool _readOnly = widget.provider.isReadOnly;
  bool _prefilled = false;
  String _initialSpending = '';
  String _initialIncome = '';
  bool _busy = false;
  String? _error;

  String get _locale => Localizations.localeOf(context).toString();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    final b = widget.budget;
    _spending.text = _initialSpending =
        budgetEditText(b.budgetedSpendingCents, b.currency, _locale);
    _income.text = _initialIncome =
        budgetEditText(b.expectedIncomeCents, b.currency, _locale);
  }

  @override
  void dispose() {
    _spending.dispose();
    _income.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    if (_canonicalAmount(value ?? '', _locale) == null) {
      return AppLocalizations.of(context).spbInvalidAmount;
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final l = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final spendingChanged = _spending.text != _initialSpending;
    final incomeChanged = _income.text != _initialIncome;
    if (!spendingChanged && !incomeChanged) {
      navigator.pop();
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final token = await widget.accessToken();
    if (!mounted) return;
    if (token == null) {
      navigator.pop();
      widget.onUnauthorized();
      return;
    }
    final result = await widget.provider.updateBudget(
      accessToken: token,
      budgetId: widget.budget.id,
      budgetedSpending:
          spendingChanged ? _canonicalAmount(_spending.text, _locale) : null,
      expectedIncome:
          incomeChanged ? _canonicalAmount(_income.text, _locale) : null,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      messenger.showSnackBar(SnackBar(content: Text(l.spbSaved)));
      navigator.pop(true);
      return;
    }
    if (result['error'] == 'unauthorized') {
      navigator.pop();
      widget.onUnauthorized();
      return;
    }
    setState(() {
      _busy = false;
      _readOnly = _readOnly || result['code'] == 'forbidden';
      _error = _saveError(l, result);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hint = formSheetAmountHint(context);
    final enabled = !_readOnly && !_busy;
    const keyboard = TextInputType.numberWithOptions(decimal: true);

    return SureSheet(
      title: l.spbEditTotals,
      actionKey: const ValueKey('budgetTotalsSave'),
      onAction: _save,
      actionEnabled: !_readOnly,
      busy: _busy,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.budget.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: SureColors.of(context).palette.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              SurePanel.rows(
                children: [
                  FormSheetFieldRow(
                    fieldKey: const ValueKey('budgetTotalsSpending'),
                    label: l.spbTotalBudget,
                    controller: _spending,
                    hint: hint,
                    validator: _validate,
                    keyboardType: keyboard,
                    mono: true,
                    enabled: enabled,
                  ),
                  FormSheetFieldRow(
                    fieldKey: const ValueKey('budgetTotalsIncome'),
                    label: l.spbExpectedIncome,
                    controller: _income,
                    hint: hint,
                    validator: _validate,
                    keyboardType: keyboard,
                    textInputAction: TextInputAction.done,
                    mono: true,
                    enabled: enabled,
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                FormErrorText(_error!),
              ],
              if (_readOnly) ...[
                const SizedBox(height: 16),
                SureBanner(
                  icon: SureIcons.info,
                  message: l.spbSharedReadOnly,
                  margin: EdgeInsets.zero,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "Spent $128 this month · avg $95": localized sentences, one per
/// (template, amount) part, with only the amounts in mono.
class _AmountSentence extends StatelessWidget {
  const _AmountSentence({
    super.key,
    required this.parts,
    required this.color,
  });

  final List<(String Function(String amount), String)> parts;
  final Color color;

  static const _marker = '\u0000';

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 13, color: color);
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (final (template, amount) in parts)
            ..._spans(template(_marker).split(_marker), amount, style),
        ],
      ),
      maxLines: 1,
      textAlign: TextAlign.center,
    );
  }

  static List<InlineSpan> _spans(
    List<String> pieces,
    String amount,
    TextStyle style,
  ) =>
      [
        TextSpan(text: pieces.first),
        TextSpan(text: amount, style: SureMoney.tabular(style)),
        if (pieces.length > 1) TextSpan(text: pieces.sublist(1).join()),
      ];
}
