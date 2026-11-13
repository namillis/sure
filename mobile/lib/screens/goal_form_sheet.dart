import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../models/goal.dart';
import '../services/goals_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../utils/amount_parser.dart';
import '../utils/money_masker.dart';
import '../widgets/ds/ds.dart';
import '../widgets/manage_widgets.dart';
import 'form_sheet_fields.dart';
import 'goals_screen.dart';

/// Icons offered for a goal: savings-shaped picks from the server's
/// `Goal::ICONS` (`Category.icon_codes`), all bundled.
const List<String> kGoalIcons = [
  'target', 'piggy-bank', 'house', 'car', 'plane', 'graduation-cap',
  'heart-pulse', 'gift', 'baby', 'shield', 'umbrella', 'briefcase', 'laptop',
  'smartphone', 'luggage', 'tree-palm', 'gem', 'wallet', 'landmark',
  'trending-up', 'coins', 'bike', 'paw-print', 'party-popper', 'trophy',
  'sparkles',
];

/// Opens the New goal sheet, or the Edit goal sheet for [goal]. Resolves to
/// the saved [Goal], or null when cancelled.
Future<Goal?> showGoalFormSheet(
  BuildContext context, {
  required GoalsService service,
  required GoalsAuth auth,
  required List<Account> accounts,
  Goal? goal,
}) {
  return showSureSheet<Goal>(
    context: context,
    builder: (_) => GoalFormSheet(
      service: service,
      auth: auth,
      accounts: accounts,
      goal: goal,
    ),
  );
}

/// [cents] in [currency]'s minor units as an editable number in [locale]
/// ("5000", "1234,5"), without grouping.
String goalAmountText(int? cents, String currency, String locale) {
  if (cents == null) return '';
  int digits;
  try {
    digits = NumberFormat.currency(name: currency).decimalDigits ?? 2;
  } catch (_) {
    digits = 2;
  }
  var text = (cents / _pow10(digits)).toStringAsFixed(digits);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'\.?0+$'), '');
  }
  final separator = NumberFormat.decimalPattern(locale).symbols.DECIMAL_SEP;
  return text.replaceAll('.', separator);
}

int _pow10(int n) {
  var result = 1;
  for (var i = 0; i < n; i++) {
    result *= 10;
  }
  return result;
}

/// The create / edit goal form (`POST`/`PATCH /api/v1/goals`): icon and
/// color, kind (one-off goal or reserve, as on the web form), name, target,
/// optional date, the funding accounts with optional earmarks, and notes.
/// The reserve's "months of expenses" mode stays on the web.
class GoalFormSheet extends StatefulWidget {
  const GoalFormSheet({
    super.key,
    required this.service,
    required this.auth,
    required this.accounts,
    this.goal,
  });

  final GoalsService service;
  final GoalsAuth auth;
  final List<Account> accounts;
  final Goal? goal;

  @override
  State<GoalFormSheet> createState() => _GoalFormSheetState();
}

/// An account in the "Fund from" list.
class _FundingOption {
  const _FundingOption(this.id, this.name, this.currency, this.subtitle);

  final String id;
  final String name;
  final String currency;
  final String? subtitle;
}

class _GoalFormSheetState extends State<GoalFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _target = TextEditingController();
  final _notes = TextEditingController();
  final Map<String, TextEditingController> _earmarks = {};
  final Set<String> _selected = {};
  late final List<_FundingOption> _options;
  String _kind = 'one_off';
  String? _color;
  String? _icon;
  DateTime? _date;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.goal != null;

  @override
  void initState() {
    super.initState();
    final goal = widget.goal;
    final linked = {for (final a in goal?.linkedAccounts ?? const <GoalLinkedAccount>[]) a.id: a};
    _options = [
      for (final a in goalFundableAccounts(widget.accounts))
        _FundingOption(a.id, a.name, a.currency, a.balance),
      // A linked account the accounts list doesn't have still shows, so
      // saving doesn't unlink it by accident.
      for (final a in linked.values)
        if (!widget.accounts.any((x) => x.id == a.id))
          _FundingOption(a.id, a.name, a.currency, null),
    ];
    for (final option in _options) {
      _earmarks[option.id] = TextEditingController();
    }
    if (goal != null) {
      _name.text = goal.name;
      _notes.text = goal.notes ?? '';
      _kind = goal.kind;
      _color = goal.color;
      _icon = goal.icon;
      _date = goal.targetDate;
      _selected.addAll(linked.keys);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || goal == null) return;
      final locale = Localizations.localeOf(context).toString();
      _target.text = goalAmountText(
          goal.targetAmount?.cents, goal.currency, locale);
      for (final a in linked.values) {
        final earmark = a.allocatedAmount;
        if (!a.wholeAccount && earmark != null) {
          _earmarks[a.id]?.text =
              goalAmountText(earmark.cents, a.currency, locale);
        }
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _notes.dispose();
    for (final c in _earmarks.values) {
      c.dispose();
    }
    super.dispose();
  }

  String get _locale => Localizations.localeOf(context).toString();

  String? _validateAmount(String? value, {required bool required}) {
    final l = AppLocalizations.of(context);
    final text = value?.trim() ?? '';
    if (text.isEmpty) return required ? l.spgTargetInvalid : null;
    try {
      final parsed = AmountParser.parse(text, locale: _locale);
      if (required ? parsed.value <= 0 : parsed.value < 0) {
        return l.spgTargetInvalid;
      }
    } on FormatException {
      return l.spgTargetInvalid;
    }
    return null;
  }

  GoalInput _input() {
    final goal = widget.goal;
    final dateText =
        _date == null ? '' : DateFormat('yyyy-MM-dd').format(_date!);
    final ids = [for (final o in _options) if (_selected.contains(o.id)) o.id];
    return GoalInput(
      name: _name.text.trim(),
      targetAmount: AmountParser.canonicalize(_target.text, locale: _locale),
      // A reserve has no date (the server clears it); a new goal without one
      // sends nothing.
      targetDate: _kind == 'maintained'
          ? null
          : (goal == null && _date == null ? null : dateText),
      color: _color,
      icon: _icon,
      notes: goal == null && _notes.text.trim().isEmpty
          ? null
          : _notes.text.trim(),
      kind: goal == null || goal.kind != _kind ? _kind : null,
      accountIds: ids,
      allocations: {
        for (final id in ids)
          id: _earmarks[id]!.text.trim().isEmpty
              ? null
              : AmountParser.canonicalize(_earmarks[id]!.text,
                  locale: _locale),
      },
    );
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    if (_selected.isEmpty) {
      setState(() => _error = l.spgAccountsRequired);
      return;
    }
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
    final input = _input();
    final goal = widget.goal;
    final result = goal == null
        ? await widget.service.createGoal(accessToken: token, goal: input)
        : await widget.service
            .updateGoal(accessToken: token, id: goal.id, goal: input);
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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _date ?? DateTime(now.year + 1, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  Future<void> _pickLook() async {
    final l = AppLocalizations.of(context);
    await showSureSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          void update(VoidCallback change) {
            setState(change);
            setSheetState(() {});
          }

          final palette = SureColors.of(sheetContext).palette;
          return SureSheet(
            title: l.spgIconAndColor,
            actionLabel: l.dsDone,
            onAction: () => Navigator.of(sheetContext).pop(),
            showCancel: false,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SureSectionHeader(
                    label: l.spgIcon,
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                  ),
                  SurePanel(
                    padding: const EdgeInsets.all(6),
                    child: Wrap(
                      spacing: 2,
                      runSpacing: 2,
                      children: [
                        for (final icon in kGoalIcons)
                          _IconChoice(
                            key: ValueKey('goalIcon-$icon'),
                            icon: icon,
                            selected: _icon == icon,
                            color: palette.textPrimary,
                            onTap: () => update(
                                () => _icon = _icon == icon ? null : icon),
                          ),
                      ],
                    ),
                  ),
                  ManageColorPicker(
                    value: _color,
                    onChanged: (hex) => update(() => _color = hex),
                    allowAutomatic: !_isEdit,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final goal = widget.goal;
    final preview = Goal(
      id: '',
      name: _name.text.isEmpty ? '?' : _name.text,
      state: 'active',
      status: '',
      displayStatus: '',
      currency: goal?.currency ?? '',
      color: _color,
      icon: _icon ?? (_name.text.trim().isEmpty ? 'target' : null),
    );
    const amountKeyboard = TextInputType.numberWithOptions(decimal: true);

    return SureSheet(
      title: _isEdit ? l.spgEditGoal : l.spgNewGoal,
      actionLabel: _isEdit ? l.commonSave : l.spgCreate,
      actionKey: const ValueKey('goalFormSave'),
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
              SurePanel.rows(
                dividerIndent: SurePanel.iconRowDividerIndent,
                children: [
                  SureListRow(
                    key: const ValueKey('goalFormLook'),
                    leading: GoalIcon(goal: preview, size: 28),
                    title: l.spgIconAndColor,
                    showChevron: true,
                    onTap: _saving ? null : _pickLook,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SureSegmentedControl<String>(
                key: const ValueKey('goalFormKind'),
                selected: _kind,
                onChanged: (kind) => setState(() => _kind = kind),
                segments: [
                  SureSegment(value: 'one_off', label: l.spgKindOneOff),
                  SureSegment(value: 'maintained', label: l.spgKindReserve),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 12),
                child: Text(
                  _kind == 'maintained'
                      ? l.spgKindReserveHint
                      : l.spgKindOneOffHint,
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
              ),
              SurePanel.rows(
                children: [
                  FormSheetFieldRow(
                    fieldKey: const ValueKey('goalFormName'),
                    label: l.spgName,
                    controller: _name,
                    hint: l.spgNameHint,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.sentences,
                    validator: (v) => (v?.trim().isEmpty ?? true)
                        ? l.spgNameRequired
                        : null,
                  ),
                  FormSheetFieldRow(
                    fieldKey: const ValueKey('goalFormTarget'),
                    label: l.spgTarget,
                    controller: _target,
                    hint: formSheetAmountHint(context),
                    keyboardType: amountKeyboard,
                    suffix: goal?.currency,
                    mono: true,
                    enabled: !_saving,
                    validator: (v) => _validateAmount(v, required: true),
                  ),
                  if (_kind != 'maintained')
                    SureListRow(
                      key: const ValueKey('goalFormDate'),
                      title: l.spgBy,
                      onTap: _saving ? null : _pickDate,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _date == null
                                ? l.spgNoDate
                                : SureDates.fullOf(context, _date!),
                            style: TextStyle(
                                fontSize: 15, color: palette.textSecondary),
                          ),
                          if (_date != null)
                            IconButton(
                              key: const ValueKey('goalFormClearDate'),
                              tooltip: l.spgNoDate,
                              visualDensity: VisualDensity.compact,
                              onPressed: _saving
                                  ? null
                                  : () => setState(() => _date = null),
                              icon: SureIcon(SureIcons.circleX,
                                  size: 18, color: palette.textSubdued),
                            )
                          else
                            Padding(
                              padding: const EdgeInsetsDirectional.only(start: 4),
                              child: SureIcon(SureIcons.chevronRight,
                                  size: 16, color: palette.textSubdued),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
              SureSectionHeader(
                label: l.spgFundFrom,
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 2),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  _options.isEmpty ? l.spgNoFundable : l.spgFundFromHint,
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
              ),
              SurePanel.rows(
                dividerIndent: SurePanel.iconRowDividerIndent,
                children: [
                  for (final option in _options)
                    _FundingRow(
                      key: ValueKey('goalFund-${option.id}'),
                      option: option,
                      checked: _selected.contains(option.id),
                      controller: _earmarks[option.id]!,
                      enabled: !_saving,
                      validator: (v) => _validateAmount(v, required: false),
                      onChanged: (checked) => setState(() {
                        checked
                            ? _selected.add(option.id)
                            : _selected.remove(option.id);
                        if (_error == l.spgAccountsRequired) _error = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              SurePanel.rows(
                children: [
                  FormSheetFieldRow(
                    fieldKey: const ValueKey('goalFormNotes'),
                    label: l.spgNotes,
                    controller: _notes,
                    hint: l.ds3fOptional,
                    maxLines: 4,
                    enabled: !_saving,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.newline,
                  ),
                ],
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

/// A 44 px icon button in the icon grid, with a check ring when selected.
class _IconChoice extends StatelessWidget {
  const _IconChoice({
    super.key,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Semantics(
      button: true,
      selected: selected,
      label: icon,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          SureHaptics.selection();
          onTap();
        },
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? palette.surfaceInset : null,
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(color: palette.textPrimary, width: 2)
                    : null,
              ),
              child: SureIcon(icon, size: 18, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

/// A checkable account row; when checked, an inline mono earmark field
/// ("Whole balance" when empty) sits at its end.
class _FundingRow extends StatelessWidget {
  const _FundingRow({
    super.key,
    required this.option,
    required this.checked,
    required this.controller,
    required this.enabled,
    required this.validator,
    required this.onChanged,
  });

  final _FundingOption option;
  final bool checked;
  final TextEditingController controller;
  final bool enabled;
  final FormFieldValidator<String> validator;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    return Semantics(
      checked: checked,
      child: InkWell(
        onTap: enabled ? () => onChanged(!checked) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 28,
                  child: Center(
                    child: checked
                        ? SureIcon(SureIcons.circleCheck,
                            size: 22, color: palette.link)
                        : Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: palette.textSubdued, width: 1.5),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: SureTokens.weightMedium,
                          color: palette.textPrimary,
                        ),
                      ),
                      if (option.subtitle != null)
                        MoneyText(
                          MoneyMasker.mask(option.subtitle!,
                              hidden: goalsAmountsHidden(context)),
                          trend: MoneyTrend.neutral,
                          color: palette.textSecondary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w400),
                        ),
                    ],
                  ),
                ),
                if (checked) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 112,
                    child: TextFormField(
                      key: ValueKey('goalEarmark-${option.id}'),
                      controller: controller,
                      enabled: enabled,
                      validator: validator,
                      textAlign: TextAlign.end,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: SureMoney.tabular(
                          TextStyle(fontSize: 15, color: palette.textPrimary)),
                      decoration: formSheetInlineDecoration(
                        palette,
                        hint: l.spgWholeBalance,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
