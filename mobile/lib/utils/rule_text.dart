import '../l10n/app_localizations.dart';
import '../models/rule.dart';

/// Kinds of record a rule condition or action value can point at by id.
enum RuleValueKind { category, tag, merchant, account }

/// Resolves the id of a [RuleValueKind] record to its name, or null when the
/// app doesn't know it.
typedef RuleNameLookup = String? Function(RuleValueKind kind, String id);

String? _noLookup(RuleValueKind kind, String id) => null;

/// Turns the conditions and actions of `GET /api/v1/rules` into sentences
/// such as "Name contains “Coffee”" or "Set category to Food". Select values
/// arrive as ids, so [lookup] maps them to names.
class RuleText {
  RuleText(this.l, {RuleNameLookup? lookup}) : _lookup = lookup ?? _noLookup;

  final AppLocalizations l;
  final RuleNameLookup _lookup;

  static const _conditionKinds = {
    'transaction_category': RuleValueKind.category,
    'transaction_tag': RuleValueKind.tag,
    'transaction_merchant': RuleValueKind.merchant,
    'transaction_account': RuleValueKind.account,
  };

  static const _actionKinds = {
    'set_transaction_category': RuleValueKind.category,
    'set_transaction_tags': RuleValueKind.tag,
    'set_transaction_merchant': RuleValueKind.merchant,
    'set_as_transfer_or_payment': RuleValueKind.account,
  };

  /// The list row title: the rule's name, else "If" plus its first condition.
  String title(Rule rule) {
    if (rule.hasName) return rule.name!.trim();
    if (rule.conditions.isEmpty) return l.p3roRuleAllTransactions;
    final first = rule.conditions.first;
    final text = first.isCompound && first.subConditions.isNotEmpty
        ? condition(first.subConditions.first)
        : condition(first);
    return l.p3roRuleIf(text);
  }

  String resourceType(String type) =>
      type == 'transaction' ? l.p3roRuleResourceTransaction : _humanize(type);

  String field(String conditionType) => switch (conditionType) {
        'transaction_name' => l.p3roRuleFieldName,
        'transaction_amount' => l.p3roRuleFieldAmount,
        'transaction_merchant' => l.p3roRuleFieldMerchant,
        'transaction_category' => l.p3roRuleFieldCategory,
        'transaction_tag' => l.p3roRuleFieldTag,
        'transaction_account' => l.p3roRuleFieldAccount,
        'transaction_type' => l.p3roRuleFieldType,
        'transaction_details' => l.p3roRuleFieldDetails,
        'transaction_notes' => l.p3roRuleFieldNotes,
        _ => _humanize(conditionType.replaceFirst('transaction_', '')),
      };

  /// One non-compound condition as a sentence.
  String condition(RuleCondition c) {
    final f = field(c.conditionType);
    final v = _conditionValue(c);
    return switch (c.operator) {
      'like' => l.p3roRuleOpContains(f, v),
      'not_like' => l.p3roRuleOpNotContains(f, v),
      'starts_with' => l.p3roRuleOpStartsWith(f, v),
      'ends_with' => l.p3roRuleOpEndsWith(f, v),
      'matches_regex' => l.p3roRuleOpRegex(f, v),
      '=' => l.p3roRuleOpEquals(f, v),
      '!=' => l.p3roRuleOpNotEquals(f, v),
      'is_null' => l.p3roRuleOpEmpty(f),
      'is_not_null' => l.p3roRuleOpNotEmpty(f),
      '>' => l.p3roRuleOpGreater(f, v),
      '>=' => l.p3roRuleOpAtLeast(f, v),
      '<' => l.p3roRuleOpLess(f, v),
      '<=' => l.p3roRuleOpAtMost(f, v),
      _ => '$f ${c.operator} $v'.trim(),
    };
  }

  /// "All of these" / "Any of these" for a compound condition.
  String compoundHeading(RuleCondition c) =>
      c.operator == 'or' ? l.p3roRuleMatchAny : l.p3roRuleMatchAll;

  /// The editor's operator pill ("contains", "is more than").
  String operatorLabel(String operator) => switch (operator) {
        'like' => l.sprOpLike,
        'not_like' => l.sprOpNotLike,
        'starts_with' => l.sprOpStartsWith,
        'ends_with' => l.sprOpEndsWith,
        'matches_regex' => l.sprOpRegex,
        '=' => l.sprOpEquals,
        '!=' => l.sprOpNotEquals,
        'is_null' => l.sprOpEmpty,
        'is_not_null' => l.sprOpNotEmpty,
        '>' => l.sprOpGreater,
        '>=' => l.sprOpAtLeast,
        '<' => l.sprOpLess,
        '<=' => l.sprOpAtMost,
        _ => operator,
      };

  /// The editor's action pill ("Set category", "Exclude from budgets and
  /// reports").
  String actionLabel(String actionType) => switch (actionType) {
        'set_transaction_category' => l.sprActSetCategory,
        'set_transaction_tags' => l.sprActAddTags,
        'set_transaction_merchant' => l.sprActSetMerchant,
        'set_transaction_name' => l.sprActRename,
        'set_investment_activity_label' => l.sprActActivity,
        'set_as_transfer_or_payment' => l.sprActTransfer,
        _ => action(RuleAction(actionType: actionType)),
      };

  /// `income` / `expense` / `transfer` as words.
  String transactionType(String value) => switch (value) {
        'income' => l.p3roRuleTypeIncome,
        'expense' => l.p3roRuleTypeExpense,
        'transfer' => l.p3roRuleTypeTransfer,
        _ => value,
      };

  /// The name of a [kind] record, or null when the app doesn't know [id].
  String? nameOf(RuleValueKind kind, String id) => _lookup(kind, id);

  String action(RuleAction a) {
    final v = _actionValue(a);
    return switch (a.actionType) {
      'set_transaction_category' => l.p3roRuleActionSetCategory(v),
      'set_transaction_tags' => l.p3roRuleActionAddTag(v),
      'set_transaction_merchant' => l.p3roRuleActionSetMerchant(v),
      'set_transaction_name' => l.p3roRuleActionRename(v),
      'set_as_transfer_or_payment' => l.p3roRuleActionTransfer(v),
      'set_investment_activity_label' => l.p3roRuleActionActivityLabel(v),
      'exclude_transaction' => l.p3roRuleActionExclude,
      'auto_categorize' => l.p3roRuleActionAutoCategorize,
      'auto_detect_merchants' => l.p3roRuleActionAutoMerchants,
      'bayes_categorize' => l.p3roRuleActionClassifier,
      'fill_similar_merchants' => l.p3roRuleActionFillMerchants,
      'send_email_notification' => l.p3roRuleActionEmail,
      'split_transaction' => l.p3roRuleActionSplit,
      _ => _humanize(a.actionType),
    };
  }

  String _conditionValue(RuleCondition c) {
    final raw = c.value?.trim() ?? '';
    final kind = _conditionKinds[c.conditionType];
    if (kind != null) return _named(kind, raw);
    if (c.conditionType == 'transaction_type') return transactionType(raw);
    if (c.conditionType == 'transaction_amount') return raw;
    return l.p3roRuleQuoted(raw);
  }

  String _actionValue(RuleAction a) {
    final raw = a.value?.trim() ?? '';
    if (a.actionType == 'set_transaction_tags' && raw.contains(',')) {
      return raw
          .split(',')
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .map((id) => _named(RuleValueKind.tag, id))
          .join(', ');
    }
    final kind = _actionKinds[a.actionType];
    if (kind != null) return _named(kind, raw);
    if (a.actionType == 'set_transaction_name') return l.p3roRuleQuoted(raw);
    return raw;
  }

  String _named(RuleValueKind kind, String id) {
    final name = id.isEmpty ? null : _lookup(kind, id);
    if (name != null && name.trim().isNotEmpty) return name;
    return switch (kind) {
      RuleValueKind.category => l.p3roRuleSomeCategory,
      RuleValueKind.tag => l.p3roRuleSomeTag,
      RuleValueKind.merchant => l.p3roRuleSomeMerchant,
      RuleValueKind.account => l.p3roRuleSomeAccount,
    };
  }

  static String _humanize(String key) {
    final words = key.replaceAll('_', ' ').trim();
    if (words.isEmpty) return key;
    return words[0].toUpperCase() + words.substring(1);
  }
}
