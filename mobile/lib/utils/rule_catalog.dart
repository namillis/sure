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
}

/// One condition type of the registry.
class RuleConditionSpec {
  const RuleConditionSpec(this.key, this.operators, this.input);

  final String key;

  /// Operator values in the server's order.
  final List<String> operators;
  final RuleValueInput input;
}

/// One action type of the registry.
class RuleActionSpec {
  const RuleActionSpec(this.key, this.input, {this.offeredForNew = true});

  final String key;
  final RuleValueInput input;

  /// False for actions the editor keeps on a rule but doesn't offer when
  /// adding: split (structured config, web only) and the AI actions, which
  /// the server offers only while an AI provider is configured — something
  /// the API doesn't report.
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
