/// The condition and action types the Sure server's rule registry accepts,
/// for the native rule editor. Hand-copied from the server; keep in step:
///
/// - Condition order and types: `Rule::Registry::TransactionResource::
///   CONDITION_FILTER_CLASSES` (app/models/rule/registry/transaction_resource.rb),
///   each filter's `type` and `operators` in app/models/rule/condition_filter/*.rb,
///   and the operator lists in `Rule::ConditionFilter::OPERATORS_MAP`
///   (app/models/rule/condition_filter.rb).
/// - Valueless operators: `Rule::ConditionFilter::VALUELESS_OPERATORS`.
/// - Compound conditions: `condition_type: "compound"` with operator `and` /
///   `or` (app/views/rule/conditions/_condition_group.html.erb), one level
///   deep (`Rule#no_nested_compound_conditions`).
/// - Action order and value types: `ACTION_EXECUTOR_CLASSES` in the same
///   registry file and each executor's `type` in
///   app/models/rule/action_executor/*.rb.
/// - Investment activity labels: `Transaction::ACTIVITY_LABELS`
///   (app/models/transaction.rb).
library;

/// What a condition or action value is, which decides its input.
enum RuleValueInput {
  /// Free text.
  text,

  /// A number (the amount condition compares `ABS(amount)`).
  amount,
  category,
  merchant,

  /// One tag (condition) or several, comma-separated (action).
  tag,
  account,

  /// `income` / `expense` / `transfer`.
  transactionType,

  /// One of [ruleActivityLabels].
  activityLabel,

  /// No value (function actions).
  none,

  /// A structured value the app can't edit (split config); kept as is.
  unsupported,

  /// One of the spec's [RuleConditionSpec.options] (server catalog).
  select,

  /// Several of the spec's options, comma-separated (server catalog).
  multiSelect,

  /// The split editor (server catalog): `split_rows`.
  split,
}

/// One choice of a catalog select.
class RuleOptionSpec {
  const RuleOptionSpec(this.value, this.label);

  final String value;
  final String label;
}

/// One condition type of the registry.
class RuleConditionSpec {
  const RuleConditionSpec(
    this.key,
    this.operators,
    this.input, {
    this.label,
    this.operatorLabels = const {},
    this.valuelessOperators,
    this.options,
  });

  final String key;

  /// Operator values in the server's order.
  final List<String> operators;
  final RuleValueInput input;

  /// The server's label; null uses the app's own wording.
  final String? label;

  /// The server's (localized) operator labels by key.
  final Map<String, String> operatorLabels;

  /// Operators with `requires_value: false`; null uses
  /// [ruleValuelessOperators].
  final Set<String>? valuelessOperators;

  /// Choices for [RuleValueInput.select].
  final List<RuleOptionSpec>? options;

  bool needsValue(String operator) =>
      !(valuelessOperators ?? ruleValuelessOperators).contains(operator);
}

/// One action type of the registry.
class RuleActionSpec {
  const RuleActionSpec(
    this.key,
    this.input, {
    this.offeredForNew = true,
    this.label,
    this.options,
  });

  final String key;
  final RuleValueInput input;

  /// The server's label; null uses the app's own wording.
  final String? label;

  /// Choices for [RuleValueInput.select] / [RuleValueInput.multiSelect].
  final List<RuleOptionSpec>? options;

  /// False for actions the editor keeps on a rule but doesn't offer when
  /// adding: split (structured config, web only) and the AI actions, which
  /// the server offers only while an AI provider is configured — something
  /// the API doesn't report. From the server catalog: its `available`.
  final bool offeredForNew;
}

/// `OPERATORS_MAP["text"]`.
const ruleTextOperators = [
  'like',
  'not_like',
  'starts_with',
  'ends_with',
  'matches_regex',
  '=',
  '!=',
  'is_null',
  'is_not_null',
];

/// `OPERATORS_MAP["number"]`.
const ruleNumberOperators = ['>', '>=', '<', '<=', '=', '!='];

/// `OPERATORS_MAP["select"]`.
const ruleSelectOperators = ['=', '!=', 'is_null', 'is_not_null'];

/// `Rule::ConditionFilter::VALUELESS_OPERATORS`.
const ruleValuelessOperators = {'is_null', 'is_not_null'};

const ruleCompoundType = 'compound';

/// In the registry's order.
const ruleConditionSpecs = [
  RuleConditionSpec('transaction_name', ruleTextOperators, RuleValueInput.text),
  RuleConditionSpec(
      'transaction_amount', ruleNumberOperators, RuleValueInput.amount),
  // TransactionType#operators: only "=".
  RuleConditionSpec(
      'transaction_type', ['='], RuleValueInput.transactionType),
  RuleConditionSpec(
      'transaction_merchant', ruleSelectOperators, RuleValueInput.merchant),
  RuleConditionSpec(
      'transaction_category', ruleSelectOperators, RuleValueInput.category),
  RuleConditionSpec('transaction_tag', ruleSelectOperators, RuleValueInput.tag),
  // TransactionDetails#operators: contains, equal to, is empty.
  RuleConditionSpec(
      'transaction_details', ['like', '=', 'is_null'], RuleValueInput.text),
  RuleConditionSpec(
      'transaction_notes', ruleTextOperators, RuleValueInput.text),
  RuleConditionSpec(
      'transaction_account', ruleSelectOperators, RuleValueInput.account),
];

/// In the registry's order.
const ruleActionSpecs = [
  RuleActionSpec('set_transaction_category', RuleValueInput.category),
  RuleActionSpec('set_transaction_tags', RuleValueInput.tag),
  RuleActionSpec('set_transaction_merchant', RuleValueInput.merchant),
  RuleActionSpec('set_transaction_name', RuleValueInput.text),
  RuleActionSpec('set_investment_activity_label', RuleValueInput.activityLabel),
  RuleActionSpec('exclude_transaction', RuleValueInput.none),
  RuleActionSpec('set_as_transfer_or_payment', RuleValueInput.account),
  RuleActionSpec('split_transaction', RuleValueInput.unsupported,
      offeredForNew: false),
  RuleActionSpec('send_email_notification', RuleValueInput.none),
  RuleActionSpec('fill_similar_merchants', RuleValueInput.none),
  RuleActionSpec('bayes_categorize', RuleValueInput.none),
  RuleActionSpec('auto_categorize', RuleValueInput.none, offeredForNew: false),
  RuleActionSpec('auto_detect_merchants', RuleValueInput.none,
      offeredForNew: false),
];

/// `TransactionType#options` values.
const ruleTransactionTypes = ['income', 'expense', 'transfer'];

/// `Transaction::ACTIVITY_LABELS`; the server stores and shows them as is.
const ruleActivityLabels = [
  'Buy',
  'Sell',
  'Sweep In',
  'Sweep Out',
  'Dividend',
  'Reinvestment',
  'Interest',
  'Fee',
  'Transfer',
  'Contribution',
  'Withdrawal',
  'Exchange',
  'Other',
];

RuleConditionSpec? ruleConditionSpec(String key) =>
    ruleConditionSpecs.where((s) => s.key == key).firstOrNull;

RuleActionSpec? ruleActionSpec(String key) =>
    ruleActionSpecs.where((s) => s.key == key).firstOrNull;

bool ruleOperatorNeedsValue(String operator) =>
    !ruleValuelessOperators.contains(operator);

/// The condition and action types the rule editor offers: the hand-written
/// lists above ([RuleEditorCatalog.builtIn]), or the server's own from
/// `GET /api/v1/rules/catalog` (Sure+ `rules.catalog`, built from the same
/// registry, with labels, options and AI availability).
class RuleEditorCatalog {
  const RuleEditorCatalog({
    required this.conditions,
    required this.actions,
    this.fromServer = false,
  });

  const RuleEditorCatalog.builtIn()
      : conditions = ruleConditionSpecs,
        actions = ruleActionSpecs,
        fromServer = false;

  /// Parses the catalog body. Unknown value types become text (conditions)
  /// or [RuleValueInput.unsupported] (actions).
  factory RuleEditorCatalog.fromJson(Map<String, dynamic> json) {
    List<RuleOptionSpec>? options(dynamic raw) => raw is List
        ? [
            for (final o in raw.whereType<Map>())
              RuleOptionSpec('${o['value']}', '${o['label'] ?? o['value']}'),
          ]
        : null;

    final conditions = <RuleConditionSpec>[];
    for (final c in (json['conditions'] as List? ?? const []).whereType<Map>()) {
      final ops = (c['operators'] as List? ?? const []).whereType<Map>();
      final type = c['type']?.toString();
      final opts = options(c['options']);
      conditions.add(RuleConditionSpec(
        '${c['key']}',
        [for (final o in ops) '${o['key']}'],
        switch (type) {
          'number' => RuleValueInput.amount,
          'select' when opts != null => RuleValueInput.select,
          _ => RuleValueInput.text,
        },
        label: c['label']?.toString(),
        operatorLabels: {
          for (final o in ops)
            if (o['label'] != null) '${o['key']}': '${o['label']}',
        },
        valuelessOperators: {
          for (final o in ops)
            if (o['requires_value'] == false) '${o['key']}',
        },
        options: opts,
      ));
    }

    final actions = <RuleActionSpec>[];
    for (final a in (json['actions'] as List? ?? const []).whereType<Map>()) {
      final opts = options(a['options']);
      actions.add(RuleActionSpec(
        '${a['key']}',
        switch (a['value_type']?.toString()) {
          'function' => RuleValueInput.none,
          'text' => RuleValueInput.text,
          'select' when opts != null => RuleValueInput.select,
          'multi_select' when opts != null => RuleValueInput.multiSelect,
          'split' => RuleValueInput.split,
          _ => RuleValueInput.unsupported,
        },
        offeredForNew: a['available'] != false,
        label: a['label']?.toString(),
        options: opts,
      ));
    }
    return RuleEditorCatalog(
        conditions: conditions, actions: actions, fromServer: true);
  }

  final List<RuleConditionSpec> conditions;
  final List<RuleActionSpec> actions;
  final bool fromServer;

  RuleConditionSpec? condition(String key) =>
      conditions.where((s) => s.key == key).firstOrNull;

  RuleActionSpec? action(String key) =>
      actions.where((s) => s.key == key).firstOrNull;

  /// The options a split row offers for [kind]: the matching action's (the
  /// split executor sends none of its own), else the condition's.
  List<RuleOptionSpec> splitOptions(String kind) =>
      action('set_transaction_$kind')?.options ??
      condition('transaction_$kind')?.options ??
      const [];
}
