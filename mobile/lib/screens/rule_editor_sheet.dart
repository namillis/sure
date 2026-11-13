import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/category.dart';
import '../models/rule.dart';
import '../providers/accounts_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/merchants_provider.dart';
import '../providers/server_features_provider.dart';
import '../providers/tags_provider.dart';
import '../services/rules_service.dart';
import '../theme/sure_colors.dart';
import '../utils/amount_parser.dart';
import '../utils/rule_catalog.dart';
import '../utils/rule_text.dart';
import '../widgets/category_picker_sheet.dart';
import '../widgets/ds/ds.dart';
import '../widgets/manage_widgets.dart';
import '../widgets/metadata_picker_sheet.dart';
import 'form_sheet_fields.dart';

/// True when the server can create and edit rules (Sure+ `rules.write`).
/// Watches [ServerFeaturesProvider]; false when it isn't mounted.
bool rulesWriteEnabled(BuildContext context) {
  try {
    return Provider.of<ServerFeaturesProvider>(context)
        .has(ServerFeaturesProvider.rulesWrite);
  } on ProviderNotFoundException {
    return false;
  }
}

/// The records the editor's value pickers offer.
class RuleEditorChoices {
  const RuleEditorChoices({
    this.categories = const [],
    this.merchants = const [],
    this.tags = const [],
    this.accounts = const [],
  });

  final List<Category> categories;
  final List<PickerOption> merchants;
  final List<PickerOption> tags;
  final List<PickerOption> accounts;

  /// From the app's category, merchant, tag and account providers (each
  /// empty when its provider isn't mounted).
  factory RuleEditorChoices.fromProviders(BuildContext context) {
    T? maybe<T>() {
      try {
        return Provider.of<T>(context, listen: false);
      } on ProviderNotFoundException {
        return null;
      }
    }

    return RuleEditorChoices(
      categories: maybe<CategoriesProvider>()?.categories ?? const [],
      merchants: [
        for (final m in maybe<MerchantsProvider>()?.merchants ?? const [])
          PickerOption(id: m.id, label: m.name),
      ],
      tags: [
        for (final t in maybe<TagsProvider>()?.tags ?? const [])
          PickerOption(id: t.id, label: t.name),
      ],
      accounts: [
        for (final a in maybe<AccountsProvider>()?.accounts ?? const [])
          PickerOption(id: a.id, label: a.name),
      ],
    );
  }

  String? nameOf(RuleValueKind kind, String id) => switch (kind) {
        RuleValueKind.category =>
          categories.where((c) => c.id == id).firstOrNull?.name,
        RuleValueKind.merchant =>
          merchants.where((o) => o.id == id).firstOrNull?.label,
        RuleValueKind.tag => tags.where((o) => o.id == id).firstOrNull?.label,
        RuleValueKind.account =>
          accounts.where((o) => o.id == id).firstOrNull?.label,
      };
}

/// What a saved editor returns: the rule as the server stored it and any
/// `warnings` it sent.
class RuleEditorResult {
  const RuleEditorResult(this.rule, this.warnings);

  final Rule rule;
  final List<String> warnings;
}

/// Sends the `rule` body (see [ruleWriteBody]) and returns the
/// [RulesService] result map.
typedef RuleEditorSave = Future<Map<String, dynamic>> Function(
    Map<String, dynamic> body);

/// Opens the rule editor: [existing] edits that rule, [copyOf] starts a new
/// rule prefilled from it (Duplicate), neither starts an empty one. Resolves
/// to the saved rule, or null when cancelled.
Future<RuleEditorResult?> showRuleEditorSheet(
  BuildContext context, {
  required RuleEditorSave save,
  required RuleEditorChoices choices,
  Rule? existing,
  Rule? copyOf,
}) {
  return showSureSheet<RuleEditorResult>(
    context: context,
    isDismissible: false,
    builder: (_) => RuleEditorSheet(
      save: save,
      choices: choices,
      existing: existing,
      copyOf: copyOf,
    ),
  );
}

class _ConditionDraft {
  _ConditionDraft({
    this.id,
    required this.type,
    required this.operator,
    this.value,
    List<_ConditionDraft>? subs,
  }) : subs = subs ?? [];

  factory _ConditionDraft.from(RuleCondition c, {required bool keepIds}) =>
      _ConditionDraft(
        id: keepIds ? c.id : null,
        type: c.conditionType,
        operator: c.operator,
        value: c.value,
        subs: [
          for (final s in c.subConditions)
            _ConditionDraft.from(s, keepIds: keepIds),
        ],
      );

  /// A new "Name contains …" row: the registry's first condition type.
  factory _ConditionDraft.blank() {
    final spec = ruleConditionSpecs.first;
    return _ConditionDraft(type: spec.key, operator: spec.operators.first);
  }

  final String? id;
  String type;
  String operator;
  String? value;
  final List<_ConditionDraft> subs;
  final Key key = UniqueKey();

  bool get isCompound => type == ruleCompoundType;

  RuleCondition toCondition() => RuleCondition(
        id: id,
        conditionType: type,
        operator: operator,
        value: isCompound || !ruleOperatorNeedsValue(operator) ? null : value,
        subConditions: [for (final s in subs) s.toCondition()],
      );
}

class _ActionDraft {
  _ActionDraft({this.id, required this.type, this.value});

  final String? id;
  String type;
  String? value;
  final Key key = UniqueKey();

  RuleValueInput get input =>
      ruleActionSpec(type)?.input ?? RuleValueInput.unsupported;

  RuleAction toAction() => RuleAction(
        id: id,
        actionType: type,
        value: input == RuleValueInput.none ? null : value,
      );
}

bool _blank(String? value) => value == null || value.trim().isEmpty;

/// The New rule / Edit rule sheet (Sure+ `rules.write`): name and active
/// switch, the conditions as "[field] [operator] [value]" sentences with
/// one level of all/any groups, and the actions as "[action] [value]". Each
/// bracket is a pill that opens a picker. Types, operators and value kinds
/// come from [ruleConditionSpecs] / [ruleActionSpecs] (the server registry).
class RuleEditorSheet extends StatefulWidget {
  const RuleEditorSheet({
    super.key,
    required this.save,
    required this.choices,
    this.existing,
    this.copyOf,
  });

  final RuleEditorSave save;
  final RuleEditorChoices choices;
  final Rule? existing;
  final Rule? copyOf;

  @override
  State<RuleEditorSheet> createState() => _RuleEditorSheetState();
}

class _RuleEditorSheetState extends State<RuleEditorSheet> {
  late final TextEditingController _name;
  late bool _active;
  late final List<_ConditionDraft> _conditions;
  late final List<_ActionDraft> _actions;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final source = widget.existing ?? widget.copyOf;
    final keepIds = widget.existing != null;
    _active = source?.active ?? true;
    _name = TextEditingController(text: source?.name?.trim() ?? '');
    _conditions = [
      for (final c in source?.conditions ?? const <RuleCondition>[])
        _ConditionDraft.from(c, keepIds: keepIds),
    ];
    if (source == null) _conditions.add(_ConditionDraft.blank());
    _actions = [
      for (final a in source?.actions ?? const <RuleAction>[])
        _ActionDraft(
            id: keepIds ? a.id : null, type: a.actionType, value: a.value),
    ];
    if (source == null) _actions.add(_ActionDraft(type: _offeredActions.first));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final copy = widget.copyOf;
    if (copy != null && copy.hasName && _name.text == copy.name!.trim()) {
      _name.text =
          AppLocalizations.of(context).sprRuleCopyName(copy.name!.trim());
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  RuleText _text(AppLocalizations l) =>
      RuleText(l, lookup: widget.choices.nameOf);

  /// Action types that can still be added: offered ones not on the rule
  /// (the server rejects duplicate action types).
  List<String> get _offeredActions {
    final used = _actions.map((a) => a.type).toSet();
    return [
      for (final spec in ruleActionSpecs)
        if (spec.offeredForNew && !used.contains(spec.key)) spec.key,
    ];
  }

  /// A split must be the rule's only action (`Rule#split_is_only_action`).
  bool get _canAddAction =>
      _offeredActions.isNotEmpty &&
      !_actions.any((a) => a.type == 'split_transaction');

  String? _validate(AppLocalizations l) {
    if (_actions.isEmpty) return l.sprRuleNeedsAction;
    bool missing(_ConditionDraft c) =>
        ruleOperatorNeedsValue(c.operator) && _blank(c.value);
    for (final c in _conditions) {
      if (c.isCompound) {
        if (c.subs.isEmpty) return l.sprRuleEmptyGroup;
        if (c.subs.any(missing)) return l.sprRuleMissingValue;
      } else if (missing(c)) {
        return l.sprRuleMissingValue;
      }
    }
    for (final a in _actions) {
      final needsValue =
          a.input != RuleValueInput.none && a.input != RuleValueInput.unsupported;
      if (needsValue && _blank(a.value)) return l.sprRuleMissingValue;
    }
    return null;
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final invalid = _validate(l);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = ruleWriteBody(
      name: _name.text,
      active: _active,
      conditions: [for (final c in _conditions) c.toCondition()],
      actions: [for (final a in _actions) a.toAction()],
      copyOf: widget.copyOf,
    );
    final result = await widget.save(body);
    if (!mounted) return;
    if (result['success'] == true) {
      Navigator.of(context).pop(RuleEditorResult(
        result['rule'] as Rule,
        (result['warnings'] as List?)?.cast<String>() ?? const [],
      ));
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

  void _edit(VoidCallback change) {
    setState(() {
      change();
      _error = null;
    });
  }

  // Pickers ----------------------------------------------------------------

  Future<void> _pickField(_ConditionDraft c) async {
    final l = AppLocalizations.of(context);
    final text = _text(l);
    final picked = await showManageOptionSheet<String>(
      context,
      title: l.sprRulePickField,
      options: [
        for (final spec in ruleConditionSpecs) (spec.key, text.field(spec.key)),
      ],
      selected: c.type,
    );
    if (picked == null || picked.value == c.type) return;
    final spec = ruleConditionSpec(picked.value)!;
    final oldInput = ruleConditionSpec(c.type)?.input;
    _edit(() {
      c.type = spec.key;
      if (!spec.operators.contains(c.operator)) {
        c.operator = spec.operators.first;
      }
      if (oldInput != spec.input) c.value = null;
    });
  }

  Future<void> _pickOperator(_ConditionDraft c) async {
    final l = AppLocalizations.of(context);
    final text = _text(l);
    final operators = ruleConditionSpec(c.type)?.operators ?? [c.operator];
    final picked = await showManageOptionSheet<String>(
      context,
      title: l.sprRulePickOperator,
      options: [for (final op in operators) (op, text.operatorLabel(op))],
      selected: c.operator,
    );
    if (picked == null) return;
    _edit(() {
      c.operator = picked.value;
      if (!ruleOperatorNeedsValue(c.operator)) c.value = null;
    });
  }

  Future<void> _pickGroup(_ConditionDraft c) async {
    final l = AppLocalizations.of(context);
    final picked = await showManageOptionSheet<String>(
      context,
      title: l.sprRulePickGroup,
      options: [('and', l.p3roRuleMatchAll), ('or', l.p3roRuleMatchAny)],
      selected: c.operator,
    );
    if (picked != null) _edit(() => c.operator = picked.value);
  }

  Future<void> _pickActionType(_ActionDraft a) async {
    final l = AppLocalizations.of(context);
    final text = _text(l);
    final options = [a.type, ..._offeredActions];
    final picked = await showManageOptionSheet<String>(
      context,
      title: l.sprRulePickAction,
      options: [for (final key in options) (key, text.actionLabel(key))],
      selected: a.type,
    );
    if (picked == null || picked.value == a.type) return;
    final oldInput = a.input;
    _edit(() {
      a.type = picked.value;
      if (a.input != oldInput) a.value = null;
    });
  }

  /// Opens the picker or field for a value of kind [input]; returns the new
  /// value, or null when dismissed.
  Future<String?> _pickValue(
    RuleValueInput input, {
    required String title,
    required String? current,
    bool multiTags = false,
  }) async {
    final l = AppLocalizations.of(context);
    final text = _text(l);
    final choices = widget.choices;
    switch (input) {
      case RuleValueInput.text:
      case RuleValueInput.amount:
        return showSureSheet<String>(
          context: context,
          builder: (_) => _RuleValueField(
            title: title,
            initial: current ?? '',
            amount: input == RuleValueInput.amount,
          ),
        );
      case RuleValueInput.category:
        final picked = await CategoryPickerSheet.show(
          context,
          categories: choices.categories,
          selectedId: current,
        );
        return picked?.id;
      case RuleValueInput.merchant:
      case RuleValueInput.account:
      case RuleValueInput.tag:
        final options = switch (input) {
          RuleValueInput.merchant => choices.merchants,
          RuleValueInput.account => choices.accounts,
          _ => choices.tags,
        };
        final selected = (current ?? '')
            .split(',')
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toSet();
        final picked = await MetadataPickerSheet.show(
          context,
          title: title,
          options: options,
          initialSelection: multiTags ? selected : selected.take(1).toSet(),
          multiSelect: multiTags,
        );
        if (picked == null) return null;
        if (multiTags) {
          // Keep the options' order, so the value is stable.
          return [
            for (final o in options)
              if (picked.contains(o.id)) o.id,
            for (final id in picked)
              if (!options.any((o) => o.id == id)) id,
          ].join(',');
        }
        return picked.firstOrNull;
      case RuleValueInput.transactionType:
        final picked = await showManageOptionSheet<String?>(
          context,
          title: title,
          options: [
            for (final t in ruleTransactionTypes) (t, text.transactionType(t)),
          ],
          selected: current,
        );
        return picked?.value;
      case RuleValueInput.activityLabel:
        final picked = await showManageOptionSheet<String?>(
          context,
          title: title,
          options: [for (final label in ruleActivityLabels) (label, label)],
          selected: current,
        );
        return picked?.value;
      case RuleValueInput.none:
      case RuleValueInput.unsupported:
        return null;
    }
  }

  /// The value pill's text, or null for "not set".
  String? _valueLabel(RuleValueInput input, String? value, RuleText text) {
    if (_blank(value)) return null;
    final raw = value!.trim();
    final l = text.l;
    String named(RuleValueKind kind, String some) =>
        widget.choices.nameOf(kind, raw) ?? some;
    return switch (input) {
      RuleValueInput.text => l.p3roRuleQuoted(value),
      RuleValueInput.amount => raw,
      RuleValueInput.category =>
        named(RuleValueKind.category, l.p3roRuleSomeCategory),
      RuleValueInput.merchant =>
        named(RuleValueKind.merchant, l.p3roRuleSomeMerchant),
      RuleValueInput.account =>
        named(RuleValueKind.account, l.p3roRuleSomeAccount),
      RuleValueInput.tag => _tagsLabel(raw, l),
      RuleValueInput.transactionType => text.transactionType(raw),
      RuleValueInput.activityLabel => raw,
      RuleValueInput.none || RuleValueInput.unsupported => null,
    };
  }

  String _tagsLabel(String raw, AppLocalizations l) {
    final ids = raw.split(',').where((id) => id.trim().isNotEmpty).toList();
    if (ids.length > 2) return l.sprRuleTagsCount(ids.length);
    return ids
        .map((id) =>
            widget.choices.nameOf(RuleValueKind.tag, id.trim()) ??
            l.p3roRuleSomeTag)
        .join(', ');
  }

  // Rows -------------------------------------------------------------------

  Widget _conditionRow(_ConditionDraft c, List<_ConditionDraft> owner,
      RuleText text) {
    final l = text.l;
    final spec = ruleConditionSpec(c.type);
    final input = spec?.input ?? RuleValueInput.text;
    final field = text.field(c.type);
    return _SentenceRow(
      key: c.key,
      removeLabel: l.sprRuleRemove,
      onRemove: () => _edit(() => owner.remove(c)),
      pills: [
        RuleEditorPill(
          key: ValueKey('ruleField-${c.key}'),
          label: field,
          onTap: () => _pickField(c),
        ),
        RuleEditorPill(
          key: ValueKey('ruleOperator-${c.key}'),
          label: text.operatorLabel(c.operator),
          onTap: () => _pickOperator(c),
        ),
        if (ruleOperatorNeedsValue(c.operator))
          _valuePill(
            key: ValueKey('ruleValue-${c.key}'),
            input: input,
            value: c.value,
            text: text,
            title: field,
            onPicked: (v) => _edit(() => c.value = v),
          ),
      ],
    );
  }

  Widget _valuePill({
    required Key key,
    required RuleValueInput input,
    required String? value,
    required RuleText text,
    required String title,
    required ValueChanged<String> onPicked,
    bool multiTags = false,
  }) {
    final label = _valueLabel(input, value, text);
    return RuleEditorPill(
      key: key,
      label: label ??
          (input == RuleValueInput.text || input == RuleValueInput.amount
              ? text.l.sprRuleEnterValue
              : text.l.sprRuleChooseValue),
      placeholder: label == null,
      mono: input == RuleValueInput.amount,
      onTap: () async {
        final picked = await _pickValue(input,
            title: title, current: value, multiTags: multiTags);
        if (picked != null && mounted) onPicked(picked);
      },
    );
  }

  Widget _groupRow(_ConditionDraft group, RuleText text) {
    final l = text.l;
    return Padding(
      key: group.key,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SentenceRow(
            removeLabel: l.sprRuleRemove,
            padding: const EdgeInsets.only(left: 2),
            onRemove: () => _edit(() => _conditions.remove(group)),
            pills: [
              RuleEditorPill(
                key: ValueKey('ruleGroup-${group.key}'),
                label: text.compoundHeading(group.toCondition()),
                onTap: () => _pickGroup(group),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SurePanel.rows(
            children: [
              for (final sub in group.subs) _conditionRow(sub, group.subs, text),
              _AddRow(
                key: ValueKey('ruleGroupAdd-${group.key}'),
                label: l.sprRuleAddCondition,
                onTap: () =>
                    _edit(() => group.subs.add(_ConditionDraft.blank())),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionRow(_ActionDraft a, RuleText text) {
    final l = text.l;
    final palette = SureColors.of(context).palette;
    final split = a.input == RuleValueInput.unsupported;
    final label = text.actionLabel(a.type);
    return _SentenceRow(
      key: a.key,
      removeLabel: l.sprRuleRemove,
      onRemove: () => _edit(() => _actions.remove(a)),
      pills: [
        RuleEditorPill(
          key: ValueKey('ruleAction-${a.key}'),
          label: label,
          // A split's config is edited on the web; it is kept as is.
          onTap: split ? null : () => _pickActionType(a),
        ),
        if (split)
          Text(l.sprRuleSplitOnWeb,
              style: TextStyle(fontSize: 13, color: palette.textSecondary)),
        if (!split && a.input != RuleValueInput.none)
          _valuePill(
            key: ValueKey('ruleActionValue-${a.key}'),
            input: a.input,
            value: a.value,
            text: text,
            title: label,
            multiTags: a.type == 'set_transaction_tags',
            onPicked: (v) => _edit(() => a.value = v),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final text = _text(l);
    const header = EdgeInsets.fromLTRB(4, 16, 4, 6);

    return SureSheet(
      title: widget.existing != null ? l.sprRuleEdit : l.sprRuleNew,
      actionLabel: l.commonSave,
      actionKey: const ValueKey('ruleEditorSave'),
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
                  label: l.sprRuleName,
                  controller: _name,
                  fieldKey: const ValueKey('ruleEditorName'),
                  hint: l.sprRuleNameHint,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                ),
                SureListRow(
                  title: l.p3roRuleActive,
                  trailing: Switch.adaptive(
                    key: const ValueKey('ruleEditorActive'),
                    value: _active,
                    activeTrackColor: palette.success,
                    onChanged: (v) => _edit(() => _active = v),
                  ),
                ),
              ],
            ),
            SureSectionHeader(label: l.sprRuleIfHeader, padding: header),
            SurePanel.rows(
              children: [
                if (_conditions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Text(l.sprRuleNoConditions,
                        style: TextStyle(
                            fontSize: 13, color: palette.textSecondary)),
                  ),
                for (final c in _conditions)
                  c.isCompound
                      ? _groupRow(c, text)
                      : _conditionRow(c, _conditions, text),
                _AddRow(
                  key: const ValueKey('ruleAddCondition'),
                  label: l.sprRuleAddCondition,
                  onTap: () => _edit(() => _conditions.add(_ConditionDraft.blank())),
                ),
                _AddRow(
                  key: const ValueKey('ruleAddGroup'),
                  label: l.sprRuleAddGroup,
                  onTap: () => _edit(() => _conditions.add(_ConditionDraft(
                        type: ruleCompoundType,
                        operator: 'and',
                        subs: [_ConditionDraft.blank()],
                      ))),
                ),
              ],
            ),
            SureSectionHeader(label: l.sprRuleThenHeader, padding: header),
            SurePanel.rows(
              children: [
                for (final a in _actions) _actionRow(a, text),
                if (_canAddAction)
                  _AddRow(
                    key: const ValueKey('ruleAddAction'),
                    label: l.sprRuleAddAction,
                    onTap: () => _edit(() =>
                        _actions.add(_ActionDraft(type: _offeredActions.first))),
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

/// An outline pill in a rule sentence that opens a picker. [placeholder]
/// shows it in the subdued color; [mono] for amounts.
class RuleEditorPill extends StatelessWidget {
  const RuleEditorPill({
    super.key,
    required this.label,
    required this.onTap,
    this.placeholder = false,
    this.mono = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool placeholder;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final colors = SureColors.of(context);
    final palette = colors.palette;
    final style = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: placeholder ? palette.textSubdued : palette.textPrimary,
    );
    return Semantics(
      button: onTap != null,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(minHeight: 34),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: palette.borderPrimary),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono ? SureMoney.tabular(style) : style,
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 4),
                  SureIcon(SureIcons.chevronDown,
                      size: 14, color: palette.textSecondary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pills that wrap like a sentence, with a trailing ✕.
class _SentenceRow extends StatelessWidget {
  const _SentenceRow({
    super.key,
    required this.pills,
    required this.onRemove,
    required this.removeLabel,
    this.padding = const EdgeInsets.fromLTRB(12, 6, 0, 6),
  });

  final List<Widget> pills;
  final VoidCallback onRemove;
  final String removeLabel;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: pills,
            ),
          ),
          IconButton(
            tooltip: removeLabel,
            onPressed: onRemove,
            icon: SureIcon(SureIcons.x, size: 18, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// "＋ Add condition" in the link color.
class _AddRow extends StatelessWidget {
  const _AddRow({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return SureListRow(
      title: label,
      titleColor: palette.link,
      leading: SureIcon(SureIcons.plus, size: 18, color: palette.link),
      onTap: onTap,
    );
  }
}

/// The value sheet for a text or amount value: one field and Done.
class _RuleValueField extends StatefulWidget {
  const _RuleValueField({
    required this.title,
    required this.initial,
    required this.amount,
  });

  final String title;
  final String initial;
  final bool amount;

  @override
  State<_RuleValueField> createState() => _RuleValueFieldState();
}

class _RuleValueFieldState extends State<_RuleValueField> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The amount condition compares the absolute amount, so the sign goes.
  String? _canonicalAmount(String input) {
    try {
      final locale = Localizations.localeOf(context).toString();
      return AmountParser.parse(input, locale: locale)
          .canonicalValue
          .replaceFirst('-', '');
    } on FormatException {
      return null;
    }
  }

  void _done() {
    if (!_formKey.currentState!.validate()) return;
    final text = _controller.text;
    Navigator.of(context)
        .pop(widget.amount ? _canonicalAmount(text) ?? text : text);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    String? validator(String? value) {
      if (_blank(value)) return l.sprRuleEnterValue;
      if (widget.amount && _canonicalAmount(value!) == null) {
        return l.sprRuleAmountInvalid;
      }
      return null;
    }

    return SureSheet(
      title: widget.title,
      actionLabel: l.dsDone,
      actionKey: const ValueKey('ruleValueDone'),
      onAction: _done,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Form(
          key: _formKey,
          child: widget.amount
              ? FormSheetAmountField(
                  key: const ValueKey('ruleValueField'),
                  controller: _controller,
                  validator: validator,
                )
              : SurePanel.rows(
                  children: [
                    FormSheetFieldRow(
                      fieldKey: const ValueKey('ruleValueField'),
                      label: l.sprRulePickValue,
                      controller: _controller,
                      hint: l.sprRuleEnterValue,
                      validator: validator,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _done(),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
