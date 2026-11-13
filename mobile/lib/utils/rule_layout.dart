import '../models/rule.dart';

/// One section of the Rules list (Sure+ `rules.groups`): a group's rules, or
/// the rules without a group ([groupId] null).
class RuleBlock {
  RuleBlock({this.groupId, this.groupName, required List<Rule> rules})
      : rules = List.of(rules);

  final String? groupId;
  final String? groupName;

  /// Mutable, so reorder mode can move rules within the block.
  final List<Rule> rules;

  bool get isGroup => groupId != null;

  String get key => isGroup ? 'group:$groupId' : 'ungrouped';
}

/// Splits [rules] (in the server's `Rule.ordered` order) into one block per
/// group plus one for the ungrouped rules, each block where its first rule
/// is. The server keeps a group's rules together, so a group's block reads
/// in run order; ungrouped rules between groups are gathered into one block.
List<RuleBlock> ruleBlocks(List<Rule> rules) {
  final blocks = <String, RuleBlock>{};
  for (final rule in rules) {
    final groupId = rule.ruleGroupId;
    final block = blocks.putIfAbsent(
      groupId == null ? 'ungrouped' : 'group:$groupId',
      () => RuleBlock(
          groupId: groupId, groupName: rule.ruleGroupName, rules: const []),
    );
    block.rules.add(rule);
  }
  return blocks.values.toList();
}

/// The `rule_ids` of `PATCH /api/v1/rules/reorder` for [blocks], top to
/// bottom; each group's rules stay next to each other.
List<String> ruleBlockIds(List<RuleBlock> blocks) => [
      for (final block in blocks)
        for (final rule in block.rules) rule.id,
    ];
