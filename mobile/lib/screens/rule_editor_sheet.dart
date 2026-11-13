import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:intl/intl.dart';
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
import 'rule_groups_screen.dart';

/// True when the server can create and edit rules (Sure+ `rules.write`).
/// Watches [ServerFeaturesProvider]; false when it isn't mounted.
bool rulesWriteEnabled(BuildContext context) =>
    ruleFeatureEnabled(context, ServerFeaturesProvider.rulesWrite);

/// True when the server offers Sure+ [feature]. Watches
/// [ServerFeaturesProvider] unless [listen] is false; false when it isn't
/// mounted.
bool ruleFeatureEnabled(BuildContext context, String feature,
    {bool listen = true}) {
  try {
    return Provider.of<ServerFeaturesProvider>(context, listen: listen)
        .has(feature);
  } on ProviderNotFoundException {
    return false;
  }
}

/// What the editor needs from the server besides the rule.
class RuleEditorExtras {
  const RuleEditorExtras({required this.catalog, this.groups});

  final RuleEditorCatalog catalog;

  /// The family's groups with Sure+ `rules.groups` (empty when they
  /// failed to load); null without it, which hides the Group row.
  final List<RuleGroup>? groups;
}

/// Loads the server's rule catalog (Sure+ `rules.catalog`, cached for the
/// session; the hand-written one otherwise or on failure) and the rule
/// groups (Sure+ `rules.groups`) before the editor opens.
Future<RuleEditorExtras> loadRuleEditorExtras(
  BuildContext context, {
  required RulesService service,
  required String token,
}) async {
  final catalogOn = ruleFeatureEnabled(
      context, ServerFeaturesProvider.rulesCatalog,
      listen: false);
  final groupsOn = ruleFeatureEnabled(
      context, ServerFeaturesProvider.rulesGroups,
      listen: false);
  final locale = Localizations.localeOf(context).languageCode;
  final none = Future.value(const <String, dynamic>{});
  final results = await Future.wait([
    catalogOn ? service.getCatalog(accessToken: token, locale: locale) : none,
    groupsOn ? service.listRuleGroups(accessToken: token) : none,
  ]);
  final catalog = results[0]['catalog'];
  final groups = results[1]['groups'];
  return RuleEditorExtras(
    catalog: catalog is RuleEditorCatalog
        ? catalog
        : const RuleEditorCatalog.builtIn(),
    groups: groupsOn
        ? (groups is List ? groups.cast<RuleGroup>() : const <RuleGroup>[])
        : null,
  );
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
  RuleEditorCatalog catalog = const RuleEditorCatalog.builtIn(),
  List<RuleGroup>? groups,
}) {
  return showSureSheet<RuleEditorResult>(
    context: context,
    isDismissible: false,
    builder: (_) => RuleEditorSheet(
      save: save,
      choices: choices,
      existing: existing,
      copyOf: copyOf,
      catalog: catalog,
      groups: groups,
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
  factory _ConditionDraft.blank(RuleEditorCatalog catalog) {
    final spec = catalog.conditions.first;
    return _ConditionDraft(type: spec.key, operator: spec.operators.first);
  }

  final String? id;
  String type;
  String operator;
  String? value;
  final List<_ConditionDraft> subs;
  final Key key = UniqueKey();

  bool get isCompound => type == ruleCompoundType;

  RuleCondition toCondition(RuleEditorCatalog catalog) => RuleCondition(
        id: id,
        conditionType: type,
        operator: operator,
        value: isCompound || !_needsValue(catalog, this) ? null : value,
        subConditions: [for (final s in subs) s.toCondition(catalog)],
      );
}

/// Whether [c]'s operator takes a value, by its spec's `requires_value`.
bool _needsValue(RuleEditorCatalog catalog, _ConditionDraft c) =>
    catalog.condition(c.type)?.needsValue(c.operator) ??
    ruleOperatorNeedsValue(c.operator);

class _ActionDraft {
  _ActionDraft(this.catalog, {this.id, required this.type, this.value}) {
    if (input == RuleValueInput.split) _loadSplit();
  }

  final RuleEditorCatalog catalog;
  final String? id;
  String type;
  String? value;
  final Key key = UniqueKey();

  /// The split editor's rows and mode (`fixed` / `percentage`).
  List<RuleSplitRow> splitRows = [];
  String splitMode = 'percentage';

  /// A saved split mixing fixed and percentage rows: the editor has one
  /// mode for the whole split, so an untouched mixed split is sent back as
  /// its original value instead of being converted.
  bool _splitMixed = false;
  List<RuleSplitRow> _loadedRows = const [];
  String _loadedMode = 'percentage';

  void _loadSplit() {
    splitRows = List.of(RuleSplitRow.parseValue(value));
    if (splitRows.isNotEmpty && splitRows.every((r) => r.isFixed)) {
      splitMode = 'fixed';
    }
    _splitMixed = splitRows.any((r) => r.isFixed) &&
        splitRows.any((r) => !r.isFixed);
    _loadedRows = List.of(splitRows);
    _loadedMode = splitMode;
  }

  bool get _splitUntouched =>
      splitMode == _loadedMode &&
      splitRows.length == _loadedRows.length &&
      [
        for (var i = 0; i < splitRows.length; i++)
          identical(splitRows[i], _loadedRows[i])
      ].every((same) => same);

  /// True for a saved mixed split nobody has edited yet.
  bool get keepsSavedSplit =>
      input == RuleValueInput.split && _splitMixed && _splitUntouched;

  /// Switches to [newType], clearing the value when its kind changes.
  void changeType(String newType) {
    final oldInput = input;
    type = newType;
    if (input != oldInput || _isSelect(input)) value = null;
    if (input == RuleValueInput.split) _loadSplit();
  }

  RuleValueInput get input =>
      catalog.action(type)?.input ?? RuleValueInput.unsupported;

  RuleAction toAction() => keepsSavedSplit
      ? RuleAction(id: id, actionType: type, value: value)
      : input == RuleValueInput.split
      ? RuleAction(
          id: id,
          actionType: type,
          splitRows: [
            for (final r in splitRows) r.copyWith(type: splitMode),
          ],
        )
      : RuleAction(
          id: id,
          actionType: type,
          value: input == RuleValueInput.none ? null : value,
        );
}

bool _isSelect(RuleValueInput input) =>
    input == RuleValueInput.select || input == RuleValueInput.multiSelect;

bool _blank(String? value) => value == null || value.trim().isEmpty;

/// The New rule / Edit rule sheet (Sure+ `rules.write`): name and active
/// switch, the conditions as "[field] [operator] [value]" sentences with
/// one level of all/any groups, and the actions as "[action] [value]". Each
/// bracket is a pill that opens a picker. Types, operators and value kinds
/// come from [catalog]: the server registry's own (Sure+ `rules.catalog`)
/// or the hand-written copy. With [groups] (Sure+ `rules.groups`) a Group
/// row picks the rule's group or names a new one.
class RuleEditorSheet extends StatefulWidget {
  const RuleEditorSheet({
    super.key,
    required this.save,
    required this.choices,
    this.existing,
    this.copyOf,
    this.catalog = const RuleEditorCatalog.builtIn(),
    this.groups,
  });

  final RuleEditorSave save;
  final RuleEditorChoices choices;
  final Rule? existing;
  final Rule? copyOf;
  final RuleEditorCatalog catalog;
  final List<RuleGroup>? groups;

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

  /// The Group row: an existing group's id, or a new group's name.
  String? _groupId;
  String? _newGroupName;

  /// Set when picking a split removed the rule's other actions.
  bool _splitRemovedOthers = false;

  RuleEditorCatalog get _catalog => widget.catalog;

  @override
  void initState() {
    super.initState();
    final source = widget.existing ?? widget.copyOf;
    final keepIds = widget.existing != null;
    _active = source?.active ?? true;
    _groupId = source?.ruleGroupId;
    _name = TextEditingController(text: source?.name?.trim() ?? '');
    _conditions = [
      for (final c in source?.conditions ?? const <RuleCondition>[])
        _ConditionDraft.from(c, keepIds: keepIds),
    ];
    if (source == null) _conditions.add(_ConditionDraft.blank(_catalog));
    _actions = [
      for (final a in source?.actions ?? const <RuleAction>[])
        _ActionDraft(_catalog,
            id: keepIds ? a.id : null, type: a.actionType, value: a.value),
    ];
    if (source == null) {
      _actions.add(_ActionDraft(_catalog, type: _offeredActions.first));
    }
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
      for (final spec in _catalog.actions)
        if (spec.offeredForNew && !used.contains(spec.key)) spec.key,
    ];
  }

  /// The type "Add action" starts with: never a split next to other
  /// actions.
  String get _nextActionType => _offeredActions.firstWhere(
      (key) => _catalog.action(key)?.input != RuleValueInput.split,
      orElse: () => _offeredActions.first);

  /// A split must be the rule's only action (`Rule#split_is_only_action`).
  bool get _canAddAction =>
      _offeredActions.any(
          (key) => _catalog.action(key)?.input != RuleValueInput.split) &&
      !_actions.any((a) => a.type == 'split_transaction');

  _ActionDraft? get _splitDraft =>
      _actions.where((a) => a.input == RuleValueInput.split).firstOrNull;

  String? _validate(AppLocalizations l) {
    if (_actions.isEmpty) return l.sprRuleNeedsAction;
    bool missing(_ConditionDraft c) =>
        _needsValue(_catalog, c) && _blank(c.value);
    for (final c in _conditions) {
      if (c.isCompound) {
        if (c.subs.isEmpty) return l.sprRuleEmptyGroup;
        if (c.subs.any(missing)) return l.sprRuleMissingValue;
      } else if (missing(c)) {
        return l.sprRuleMissingValue;
      }
    }
    for (final a in _actions) {
      final needsValue = a.input != RuleValueInput.none &&
          a.input != RuleValueInput.unsupported &&
          a.input != RuleValueInput.split;
      if (needsValue && _blank(a.value)) return l.sprRuleMissingValue;
    }
    return null;
  }

  /// The exact amount an all-fixed split needs: an ANDed
  /// `transaction_amount =` condition (top level or in an all-group), as
  /// `Rule::Action#exact_amount_condition_value` reads it.
  double? _exactAmount() {
    double? find(List<_ConditionDraft> conditions) {
      for (final c in conditions) {
        if (c.isCompound) {
          if (c.operator != 'and') continue;
          final found = find(c.subs);
          if (found != null) return found;
        } else if (c.type == 'transaction_amount' && c.operator == '=') {
          final parsed = double.tryParse(c.value?.trim() ?? '');
          if (parsed != null) return parsed;
        }
      }
      return null;
    }

    return find(_conditions);
  }

  /// Why the split can't be saved yet, or null.
  String? _splitProblem(AppLocalizations l, _ActionDraft split) {
    // An untouched mixed split goes back as saved; the server validated it.
    if (split.keepsSavedSplit) return null;
    final rows = split.splitRows;
    if (rows.length < 2 || rows.length > 20) return l.sr2SplitCount;
    final total = _splitTotal(split);
    if (split.splitMode == 'percentage') {
      if ((total - 100).abs() > 0.01) return l.sr2SplitPercentTotal;
      return null;
    }
    final exact = _exactAmount();
    if (exact == null) return l.sr2SplitFixedNeedsAmount;
    if ((total - exact).abs() > 0.00005) {
      return l.sr2SplitFixedMustMatch(_formatShare(exact));
    }
    return null;
  }

  double _splitTotal(_ActionDraft split) => split.splitRows
      .fold(0.0, (sum, r) => sum + (double.tryParse(r.share) ?? 0));

  /// An amount with 2 decimals, or a percentage with up to 2.
  String _formatShare(double value, {bool percent = false}) {
    final locale = Localizations.localeOf(context).toString();
    final format = percent
        ? (NumberFormat.decimalPattern(locale)..maximumFractionDigits = 2)
        : NumberFormat.decimalPatternDigits(locale: locale, decimalDigits: 2);
    return format.format(value);
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
      conditions: [for (final c in _conditions) c.toCondition(_catalog)],
      actions: [for (final a in _actions) a.toAction()],
      copyOf: widget.copyOf,
      sendGroup: widget.groups != null,
      groupId: _groupId,
      newGroupName: _newGroupName,
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

  /// A field's name: the app's wording for the registry's known fields,
  /// else the server's label.
  String _fieldLabel(RuleText text, String key) =>
      ruleConditionSpec(key) == null
          ? _catalog.condition(key)?.label ?? text.field(key)
          : text.field(key);

  String _operatorLabel(RuleText text, String conditionType, String op) {
    final label = text.operatorLabel(op);
    if (label != op) return label;
    return _catalog.condition(conditionType)?.operatorLabels[op] ?? op;
  }

  String _actionLabel(RuleText text, String key) =>
      ruleActionSpec(key) == null
          ? _catalog.action(key)?.label ?? text.actionLabel(key)
          : text.actionLabel(key);

  Future<void> _pickField(_ConditionDraft c) async {
    final l = AppLocalizations.of(context);
    final text = _text(l);
    final picked = await showManageOptionSheet<String>(
      context,
      title: l.sprRulePickField,
      options: [
        for (final spec in _catalog.conditions)
          (spec.key, _fieldLabel(text, spec.key)),
      ],
      selected: c.type,
    );
    if (picked == null || picked.value == c.type) return;
    final spec = _catalog.condition(picked.value)!;
    final oldInput = _catalog.condition(c.type)?.input;
    _edit(() {
      c.type = spec.key;
      if (!spec.operators.contains(c.operator)) {
        c.operator = spec.operators.first;
      }
      if (oldInput != spec.input || _isSelect(spec.input)) c.value = null;
    });
  }

  Future<void> _pickOperator(_ConditionDraft c) async {
    final l = AppLocalizations.of(context);
    final text = _text(l);
    final operators = _catalog.condition(c.type)?.operators ?? [c.operator];
    final picked = await showManageOptionSheet<String>(
      context,
      title: l.sprRulePickOperator,
      options: [
        for (final op in operators) (op, _operatorLabel(text, c.type, op)),
      ],
      selected: c.operator,
    );
    if (picked == null) return;
    _edit(() {
      c.operator = picked.value;
      if (!_needsValue(_catalog, c)) c.value = null;
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
      options: [for (final key in options) (key, _actionLabel(text, key))],
      selected: a.type,
    );
    if (picked == null || picked.value == a.type) return;
    _edit(() {
      a.changeType(picked.value);
      // A split must be the rule's only action.
      if (a.input == RuleValueInput.split && _actions.length > 1) {
        _actions.removeWhere((other) => other != a);
        _splitRemovedOthers = true;
      }
    });
  }

  /// The Group row's picker: none, a group, or "New group…".
  Future<void> _pickRuleGroup() async {
    final l = AppLocalizations.of(context);
    // Group ids are UUIDs, so these can't collide with one.
    const newKey = '_new';
    const createKey = '_create';
    final groups = widget.groups ?? const <RuleGroup>[];
    final picked = await showManageOptionSheet<String?>(
      context,
      title: l.sr2RuleGroup,
      options: [
        (null, l.sr2RuleGroupNone),
        for (final g in groups) (g.id, g.name),
        if (_newGroupName != null) (newKey, _newGroupName!),
        (createKey, l.sr2RuleGroupNew),
      ],
      selected: _newGroupName != null ? newKey : _groupId,
    );
    if (picked == null || !mounted) return;
    if (picked.value == createKey) {
      final group = await showSureSheet<RuleGroup>(
        context: context,
        builder: (_) => RuleGroupNameSheet(
          initialName: '',
          isNew: true,
          // Created with the rule (`new_rule_group_name`).
          save: (name) async => {
            'success': true,
            'group': RuleGroup(id: '', name: name.trim()),
          },
        ),
      );
      if (group != null) _edit(() => _newGroupName = group.name);
      return;
    }
    if (picked.value == newKey) return;
    _edit(() {
      _newGroupName = null;
      _groupId = picked.value;
    });
  }

  String _groupLabel(AppLocalizations l) {
    if (_newGroupName != null) return _newGroupName!;
    final id = _groupId;
    if (id == null) return l.sr2RuleGroupNone;
    final source = widget.existing ?? widget.copyOf;
    return widget.groups?.where((g) => g.id == id).firstOrNull?.name ??
        (source?.ruleGroupId == id ? source?.ruleGroupName : null) ??
        l.sr2GroupUnnamed;
  }

  /// Opens the picker or field for a value of kind [input]; returns the new
  /// value, or null when dismissed.
  Future<String?> _pickValue(
    RuleValueInput input, {
    required String title,
    required String? current,
    bool multiTags = false,
    List<RuleOptionSpec>? options,
  }) async {
    final l = AppLocalizations.of(context);
    final text = _text(l);
    final choices = widget.choices;
    switch (input) {
      case RuleValueInput.select:
      case RuleValueInput.multiSelect:
        final multi = input == RuleValueInput.multiSelect;
        final pickerOptions = [
          for (final o in options ?? const <RuleOptionSpec>[])
            PickerOption(id: o.value, label: o.label),
        ];
        final selected = _ids(current);
        final picked = await MetadataPickerSheet.show(
          context,
          title: title,
          options: pickerOptions,
          initialSelection: multi ? selected : selected.take(1).toSet(),
          multiSelect: multi,
        );
        if (picked == null) return null;
        if (!multi) return picked.firstOrNull;
        return [
          for (final o in pickerOptions)
            if (picked.contains(o.id)) o.id,
          for (final id in picked)
            if (!pickerOptions.any((o) => o.id == id)) id,
        ].join(',');
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
      case RuleValueInput.split:
        return null;
    }
  }

  static Set<String> _ids(String? value) => (value ?? '')
      .split(',')
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();

  /// The value pill's text, or null for "not set".
  String? _valueLabel(RuleValueInput input, String? value, RuleText text,
      {List<RuleOptionSpec>? options}) {
    if (_blank(value)) return null;
    if (_isSelect(input)) {
      String label(String id) =>
          options?.where((o) => o.value == id).firstOrNull?.label ??
          text.l.sprRuleChooseValue;
      final ids = _ids(value).toList();
      if (ids.length > 2) return text.l.sprRuleTagsCount(ids.length);
      return ids.map(label).join(', ');
    }
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
      RuleValueInput.none ||
      RuleValueInput.unsupported ||
      RuleValueInput.select ||
      RuleValueInput.multiSelect ||
      RuleValueInput.split =>
        null,
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
    final spec = _catalog.condition(c.type);
    final input = spec?.input ?? RuleValueInput.text;
    final field = _fieldLabel(text, c.type);
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
          label: _operatorLabel(text, c.type, c.operator),
          onTap: () => _pickOperator(c),
        ),
        if (_needsValue(_catalog, c))
          _valuePill(
            key: ValueKey('ruleValue-${c.key}'),
            input: input,
            value: c.value,
            text: text,
            title: field,
            options: spec?.options,
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
    List<RuleOptionSpec>? options,
  }) {
    final label = _valueLabel(input, value, text, options: options);
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
            title: title,
            current: value,
            multiTags: multiTags,
            options: options);
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
                label: text.compoundHeading(group.toCondition(_catalog)),
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
                onTap: () => _edit(
                    () => group.subs.add(_ConditionDraft.blank(_catalog))),
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
    final webOnly = a.input == RuleValueInput.unsupported;
    final label = _actionLabel(text, a.type);
    final row = _SentenceRow(
      key: a.key,
      removeLabel: l.sprRuleRemove,
      onRemove: () => _edit(() => _actions.remove(a)),
      pills: [
        RuleEditorPill(
          key: ValueKey('ruleAction-${a.key}'),
          label: label,
          // A split's config is edited on the web; it is kept as is.
          onTap: webOnly ? null : () => _pickActionType(a),
        ),
        if (webOnly)
          Text(l.sprRuleSplitOnWeb,
              style: TextStyle(fontSize: 13, color: palette.textSecondary)),
        if (!webOnly &&
            a.input != RuleValueInput.none &&
            a.input != RuleValueInput.split)
          _valuePill(
            key: ValueKey('ruleActionValue-${a.key}'),
            input: a.input,
            value: a.value,
            text: text,
            title: label,
            multiTags: a.type == 'set_transaction_tags',
            options: _catalog.action(a.type)?.options,
            onPicked: (v) => _edit(() => a.value = v),
          ),
      ],
    );
    if (a.input != RuleValueInput.split) return row;
    return Column(
      key: ValueKey('ruleSplit-${a.key}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [row, _splitEditor(a, l)],
    );
  }

  // Split editor -----------------------------------------------------------

  String? _optionLabel(String kind, String? id) => id == null
      ? null
      : _catalog
          .splitOptions(kind)
          .where((o) => o.value == id)
          .firstOrNull
          ?.label;

  Future<void> _editSplitRow(_ActionDraft split, [int? index]) async {
    final row = await showSureSheet<RuleSplitRow>(
      context: context,
      builder: (_) => _SplitRowSheet(
        initial: index == null
            ? RuleSplitRow(type: split.splitMode)
            : split.splitRows[index],
        isNew: index == null,
        percentage: split.splitMode == 'percentage',
        categories: _catalog.splitOptions('category'),
        merchants: _catalog.splitOptions('merchant'),
      ),
    );
    if (row == null || !mounted) return;
    _edit(() {
      if (index == null) {
        split.splitRows.add(row);
      } else {
        split.splitRows[index] = row;
      }
    });
  }

  Widget _splitEditor(_ActionDraft split, AppLocalizations l) {
    final palette = SureColors.of(context).palette;
    final percentage = split.splitMode == 'percentage';
    final total = _splitTotal(split);
    final exact = percentage ? null : _exactAmount();
    final problem = _splitProblem(l, split);
    final totalText = percentage
        ? l.sr2SplitTotalPercent(_formatShare(total, percent: true))
        : exact == null
            ? l.sr2SplitTotalAmount(_formatShare(total))
            : l.sr2SplitTotalOf(_formatShare(total), _formatShare(exact));
    final secondary = TextStyle(fontSize: 13, color: palette.textSecondary);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SureSegmentedControl<String>(
            key: const ValueKey('ruleSplitMode'),
            segments: [
              SureSegment(value: 'fixed', label: l.sr2SplitFixed),
              SureSegment(value: 'percentage', label: l.sr2SplitPercentage),
            ],
            selected: split.splitMode,
            onChanged: (mode) => _edit(() => split.splitMode = mode),
          ),
          const SizedBox(height: 8),
          SurePanel.rows(
            children: [
              for (var i = 0; i < split.splitRows.length; i++)
                _splitRowTile(split, i, l),
              if (split.splitRows.length < 20)
                _AddRow(
                  key: const ValueKey('ruleSplitAdd'),
                  label: l.sr2SplitAdd,
                  onTap: () => _editSplitRow(split),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              totalText,
              key: const ValueKey('ruleSplitTotal'),
              style: SureMoney.tabular(secondary),
            ),
          ),
          if (!percentage) ...[
            const SizedBox(height: 4),
            Text(l.sr2SplitFixedHelp, style: secondary),
          ],
          if (problem != null) ...[
            const SizedBox(height: 6),
            ManageErrorText(problem, compact: true),
          ],
          if (_splitRemovedOthers) ...[
            const SizedBox(height: 6),
            Text(l.sr2SplitOnlyAction, style: secondary),
          ],
        ],
      ),
    );
  }

  Widget _splitRowTile(_ActionDraft split, int index, AppLocalizations l) {
    final palette = SureColors.of(context).palette;
    final row = split.splitRows[index];
    final share = double.tryParse(row.share);
    final shareText = share == null
        ? row.share
        : split.splitMode == 'percentage'
            ? '${_formatShare(share, percent: true)}%'
            : _formatShare(share);
    final details = [
      _optionLabel('category', row.categoryId),
      _optionLabel('merchant', row.merchantId),
    ].whereType<String>().join(' · ');
    void remove() => _edit(() => split.splitRows.removeAt(index));
    return Semantics(
      key: ValueKey('ruleSplitRow-$index'),
      customSemanticsActions: {
        CustomSemanticsAction(label: l.commonDelete): remove,
      },
      child: SureSwipeActions(
        actions: [
          SureSwipeAction(
            label: l.commonDelete,
            color: palette.destructive,
            onPressed: remove,
          ),
        ],
        child: ColoredBox(
          color: palette.container,
          child: SureListRow(
            title: row.name.trim().isEmpty ? l.sr2SplitUnnamed : row.name,
            subtitle: details.isEmpty ? l.sr2SplitNoCategory : details,
            trailing: Text(
              shareText,
              style: SureMoney.tabular(TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: palette.textPrimary,
              )),
            ),
            onTap: () => _editSplitRow(split, index),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final text = _text(l);
    const header = EdgeInsets.fromLTRB(4, 16, 4, 6);
    final split = _splitDraft;
    final splitBlocked = split != null && _splitProblem(l, split) != null;

    return SureSheet(
      title: widget.existing != null ? l.sprRuleEdit : l.sprRuleNew,
      actionLabel: l.commonSave,
      actionKey: const ValueKey('ruleEditorSave'),
      busy: _saving,
      // An invalid split is explained inline under it.
      actionEnabled: !splitBlocked,
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
                if (widget.groups != null)
                  SureListRow(
                    key: const ValueKey('ruleEditorGroup'),
                    title: l.sr2RuleGroup,
                    value: _groupLabel(l),
                    showChevron: true,
                    onTap: _pickRuleGroup,
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
                  onTap: () => _edit(
                      () => _conditions.add(_ConditionDraft.blank(_catalog))),
                ),
                _AddRow(
                  key: const ValueKey('ruleAddGroup'),
                  label: l.sprRuleAddGroup,
                  onTap: () => _edit(() => _conditions.add(_ConditionDraft(
                        type: ruleCompoundType,
                        operator: 'and',
                        subs: [_ConditionDraft.blank(_catalog)],
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
                    onTap: () => _edit(() => _actions
                        .add(_ActionDraft(_catalog, type: _nextActionType))),
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

/// Edits one split row: name, share (a percentage or an amount), category
/// and merchant. Pops the row on Done.
class _SplitRowSheet extends StatefulWidget {
  const _SplitRowSheet({
    required this.initial,
    required this.isNew,
    required this.percentage,
    required this.categories,
    required this.merchants,
  });

  final RuleSplitRow initial;
  final bool isNew;
  final bool percentage;
  final List<RuleOptionSpec> categories;
  final List<RuleOptionSpec> merchants;

  @override
  State<_SplitRowSheet> createState() => _SplitRowSheetState();
}

class _SplitRowSheetState extends State<_SplitRowSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.initial.name);
  late final TextEditingController _share =
      TextEditingController(text: widget.initial.share);
  late String? _categoryId = widget.initial.categoryId;
  late String? _merchantId = widget.initial.merchantId;

  @override
  void dispose() {
    _name.dispose();
    _share.dispose();
    super.dispose();
  }

  /// The share as a canonical positive decimal, or null.
  String? _canonicalShare(String input) {
    try {
      final locale = Localizations.localeOf(context).toString();
      final value = AmountParser.parse(input, locale: locale).canonicalValue;
      final parsed = double.tryParse(value);
      return parsed == null || parsed <= 0 ? null : value;
    } on FormatException {
      return null;
    }
  }

  Future<void> _pick(String title, List<RuleOptionSpec> options,
      String? current, ValueChanged<String?> onPicked) async {
    final picked = await MetadataPickerSheet.show(
      context,
      title: title,
      options: [
        for (final o in options) PickerOption(id: o.value, label: o.label),
      ],
      initialSelection: current == null ? const <String>{} : {current},
    );
    if (picked == null || !mounted) return;
    setState(() => onPicked(picked.firstOrNull));
  }

  void _done() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(widget.initial.copyWith(
      name: _name.text.trim(),
      share: _canonicalShare(_share.text),
      categoryId: () => _categoryId,
      merchantId: () => _merchantId,
    ));
  }

  String? _label(List<RuleOptionSpec> options, String? id) =>
      options.where((o) => o.value == id).firstOrNull?.label;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SureSheet(
      title: widget.isNew ? l.sr2SplitNew : l.sr2SplitEdit,
      actionLabel: l.dsDone,
      actionKey: const ValueKey('ruleSplitDone'),
      onAction: _done,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Form(
          key: _formKey,
          child: SurePanel.rows(
            children: [
              FormSheetFieldRow(
                label: l.sr2SplitName,
                controller: _name,
                fieldKey: const ValueKey('ruleSplitName'),
                hint: l.sr2SplitNameHint,
                textCapitalization: TextCapitalization.sentences,
                validator: (v) =>
                    _blank(v) ? l.sr2SplitNameRequired : null,
              ),
              FormSheetFieldRow(
                label: widget.percentage
                    ? l.sr2SplitSharePercent
                    : l.sr2SplitShareAmount,
                controller: _share,
                fieldKey: const ValueKey('ruleSplitShare'),
                hint: '0',
                mono: true,
                suffix: widget.percentage ? '%' : null,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                validator: (v) => _canonicalShare(v ?? '') == null
                    ? l.sr2SplitShareInvalid
                    : null,
              ),
              SureListRow(
                key: const ValueKey('ruleSplitCategory'),
                title: l.p3roRuleFieldCategory,
                value: _label(widget.categories, _categoryId) ??
                    l.sr2RuleGroupNone,
                showChevron: true,
                onTap: () => _pick(l.p3roRuleFieldCategory, widget.categories,
                    _categoryId, (id) => _categoryId = id),
              ),
              SureListRow(
                key: const ValueKey('ruleSplitMerchant'),
                title: l.p3roRuleFieldMerchant,
                value: _label(widget.merchants, _merchantId) ??
                    l.sr2RuleGroupNone,
                showChevron: true,
                onTap: () => _pick(l.p3roRuleFieldMerchant, widget.merchants,
                    _merchantId, (id) => _merchantId = id),
              ),
            ],
          ),
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
