import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/models/rule.dart';
import 'package:sure_mobile/utils/rule_text.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('en'));
  final text = RuleText(l,
      lookup: (kind, id) => switch ((kind, id)) {
            (RuleValueKind.category, 'cat1') => 'Food',
            (RuleValueKind.tag, 'tag1') => 'Work',
            _ => null,
          });

  RuleCondition cond(String type, String op, [String? value]) =>
      RuleCondition(conditionType: type, operator: op, value: value);

  test('conditions read as sentences', () {
    expect(text.condition(cond('transaction_name', 'like', 'Coffee')),
        'Name contains “Coffee”');
    expect(text.condition(cond('transaction_amount', '>=', '25.5')),
        'Amount is at least 25.5');
    expect(text.condition(cond('transaction_category', '=', 'cat1')),
        'Category is Food');
    expect(text.condition(cond('transaction_merchant', '!=', 'm9')),
        'Merchant is not a merchant');
    expect(text.condition(cond('transaction_type', '=', 'income')),
        'Type is income');
    expect(text.condition(cond('transaction_notes', 'is_null')),
        'Notes is empty');
    expect(text.condition(cond('transaction_details', 'matches_regex', r'^AB')),
        'Details matches the pattern “^AB”');
    expect(text.condition(cond('transaction_future', 'odd', 'x')),
        'Future odd “x”');
  });

  test('actions read as sentences', () {
    expect(
        text.action(const RuleAction(
            actionType: 'set_transaction_category', value: 'cat1')),
        'Set category to Food');
    expect(
        text.action(
            const RuleAction(actionType: 'set_transaction_tags', value: 'tag1')),
        'Add tag Work');
    expect(
        text.action(
            const RuleAction(actionType: 'set_transaction_name', value: 'Rent')),
        'Rename to “Rent”');
    expect(text.action(const RuleAction(actionType: 'exclude_transaction')),
        'Exclude from budgets and reports');
    expect(text.action(const RuleAction(actionType: 'brand_new_thing')),
        'Brand new thing');
  });

  test('title uses the name, else the first condition', () {
    expect(text.title(const Rule(id: 'r', name: ' Coffee ')), 'Coffee');
    expect(
        text.title(Rule(id: 'r', conditions: [
          cond('transaction_name', 'starts_with', 'SQ'),
        ])),
        'If Name starts with “SQ”');
    expect(
        text.title(Rule(id: 'r', conditions: [
          RuleCondition(
              conditionType: 'compound',
              operator: 'and',
              subConditions: [cond('transaction_amount', '<', '5')]),
        ])),
        'If Amount is less than 5');
    expect(text.title(const Rule(id: 'r')), 'All transactions');
  });

  test('compound headings', () {
    expect(text.compoundHeading(cond('compound', 'or')), 'Any of these match');
    expect(text.compoundHeading(cond('compound', 'and')), 'All of these match');
  });
}
