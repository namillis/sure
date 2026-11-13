import 'dart:convert';

/// A transaction rule from `GET /api/v1/rules` and `/api/v1/rules/:id`
/// (server: `app/views/api/v1/rules/_rule.json.jbuilder`).
class Rule {
  const Rule({
    required this.id,
    this.name,
    this.resourceType = 'transaction',
    this.active = true,
    this.effectiveDate,
    this.stopProcessing = false,
    this.ruleGroupId,
    this.ruleGroupName,
    this.position,
    this.conditions = const [],
    this.actions = const [],
  });

  final String id;

  /// Optional on the server; the web shows a summary when it's blank.
  final String? name;
  final String resourceType;
  final bool active;
  final DateTime? effectiveDate;

  /// "Stop processing other rules" on the web form.
  final bool stopProcessing;
  final String? ruleGroupId;

  /// `rule_group.name` (Sure+ `rules.groups`); null without a group.
  final String? ruleGroupName;

  /// Place in the family's rule order (Sure+ `rules.reorder`).
  final int? position;

  /// Top-level conditions; compound ones carry [RuleCondition.subConditions].
  /// The server ANDs top-level conditions (no rule-wide any/all switch).
  final List<RuleCondition> conditions;
  final List<RuleAction> actions;

  bool get hasName => (name?.trim() ?? '').isNotEmpty;

  factory Rule.fromJson(Map<String, dynamic> json) {
    final group = json['rule_group'];
    return Rule(
      id: json['id'].toString(),
      name: json['name']?.toString(),
      resourceType: json['resource_type']?.toString() ?? 'transaction',
      active: json['active'] != false,
      effectiveDate: json['effective_date'] == null
          ? null
          : DateTime.tryParse(json['effective_date'].toString()),
      stopProcessing: json['stop_processing'] == true,
      ruleGroupId: json['rule_group_id']?.toString() ??
          (group is Map ? group['id']?.toString() : null),
      ruleGroupName: group is Map ? group['name']?.toString() : null,
      position: json['position'] is num
          ? (json['position'] as num).toInt()
          : int.tryParse('${json['position'] ?? ''}'),
      conditions: _list(json['conditions'], RuleCondition.fromJson),
      actions: _list(json['actions'], RuleAction.fromJson),
    );
  }
}

/// A rule group from `GET /api/v1/rule_groups` (Sure+ `rules.groups`,
/// server: `app/views/api/v1/rule_groups/_rule_group.json.jbuilder`).
class RuleGroup {
  const RuleGroup({
    required this.id,
    required this.name,
    this.position = 0,
    this.rulesCount = 0,
  });

  final String id;
  final String name;
  final int position;
  final int rulesCount;

  factory RuleGroup.fromJson(Map<String, dynamic> json) => RuleGroup(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? '',
        position: _int(json['position']),
        rulesCount: _int(json['rules_count']),
      );
}

class RuleCondition {
  const RuleCondition({
    this.id,
    required this.conditionType,
    required this.operator,
    this.value,
    this.subConditions = const [],
  });

  /// The saved condition's id; null for one the editor added.
  final String? id;

  /// e.g. `transaction_name`, `transaction_amount`, or `compound`.
  final String conditionType;

  /// e.g. `like`, `>=`, `is_null`; `and` / `or` for compound conditions.
  final String operator;
  final String? value;
  final List<RuleCondition> subConditions;

  bool get isCompound => conditionType == 'compound';

  factory RuleCondition.fromJson(Map<String, dynamic> json) => RuleCondition(
        id: json['id']?.toString(),
        conditionType: json['condition_type']?.toString() ?? '',
        operator: json['operator']?.toString() ?? '',
        value: json['value']?.toString(),
        subConditions: _list(json['sub_conditions'], RuleCondition.fromJson),
      );

  /// The write shape of `POST`/`PATCH /api/v1/rules` (same as the read
  /// shape). The id lets a PATCH update the saved row in place; the server
  /// ignores ids on POST.
  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'condition_type': conditionType,
        'operator': operator,
        'value': value,
        if (isCompound)
          'sub_conditions': [for (final s in subConditions) s.toJson()],
      };
}

class RuleAction {
  const RuleAction({
    this.id,
    required this.actionType,
    this.value,
    this.splitRows,
  });

  /// The saved action's id; null for one the editor added.
  final String? id;

  /// e.g. `set_transaction_category`, `exclude_transaction`.
  final String actionType;

  /// A single id or text; tag ids comma-separated; a JSON config for
  /// `split_transaction`.
  final String? value;

  /// A split written as `split_rows` (Sure+ `rules.catalog`) instead of
  /// [value]; the server builds the JSON config from them.
  final List<RuleSplitRow>? splitRows;

  factory RuleAction.fromJson(Map<String, dynamic> json) => RuleAction(
        id: json['id']?.toString(),
        actionType: json['action_type']?.toString() ?? '',
        value: json['value']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'action_type': actionType,
        if (splitRows != null)
          'split_rows': [for (final r in splitRows!) r.toJson()]
        else
          'value': value,
      };
}

/// One row of a `split_transaction` action: the `splits` entries of its JSON
/// value (`{"splits":[{name, type, share, category_id, merchant_id,
/// tag_ids}]}`). [type] is `fixed` (an amount) or `percentage`.
class RuleSplitRow {
  const RuleSplitRow({
    this.name = '',
    this.type = 'percentage',
    this.share = '',
    this.categoryId,
    this.merchantId,
    this.tagIds = const [],
  });

  final String name;
  final String type;

  /// A decimal string: a percentage or an amount.
  final String share;
  final String? categoryId;
  final String? merchantId;
  final List<String> tagIds;

  bool get isFixed => type == 'fixed';

  RuleSplitRow copyWith({
    String? name,
    String? type,
    String? share,
    String? Function()? categoryId,
    String? Function()? merchantId,
  }) =>
      RuleSplitRow(
        name: name ?? this.name,
        type: type ?? this.type,
        share: share ?? this.share,
        categoryId: categoryId != null ? categoryId() : this.categoryId,
        merchantId: merchantId != null ? merchantId() : this.merchantId,
        tagIds: tagIds,
      );

  factory RuleSplitRow.fromJson(Map<String, dynamic> json) => RuleSplitRow(
        name: json['name']?.toString() ?? '',
        type: json['type']?.toString() == 'fixed' ? 'fixed' : 'percentage',
        share: json['share']?.toString() ?? '',
        categoryId: _blankToNull(json['category_id']),
        merchantId: _blankToNull(json['merchant_id']),
        tagIds: json['tag_ids'] is List
            ? [for (final t in json['tag_ids'] as List) t.toString()]
            : const [],
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'name': name,
        'share': share,
        'category_id': categoryId,
        'merchant_id': merchantId,
        'tag_ids': tagIds,
      };

  /// The rows of a split action's JSON [value]; empty when it isn't one.
  static List<RuleSplitRow> parseValue(String? value) {
    if (value == null || value.trim().isEmpty) return const [];
    try {
      final config = jsonDecode(value);
      final splits = config is Map ? config['splits'] : null;
      return _list(splits, RuleSplitRow.fromJson);
    } on FormatException {
      return const [];
    }
  }
}

String? _blankToNull(dynamic value) {
  final s = value?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

/// What `POST /api/v1/rules/:id/apply` without `confirm` reports (422
/// `confirmation_required`): the same facts the web's confirm dialog shows.
class RuleApplyConfirmation {
  const RuleApplyConfirmation({
    required this.affectedCount,
    this.ruleCount = 0,
    this.activeRulesAboveCount = 0,
    this.autoCategorize = false,
    this.aiModel,
    this.estimatedAiCost,
  });

  final int affectedCount;

  /// How many rules `POST /api/v1/rules/apply_all` would run.
  final int ruleCount;
  final int activeRulesAboveCount;
  final bool autoCategorize;
  final String? aiModel;

  /// US dollars, or null when the server can't estimate it.
  final double? estimatedAiCost;

  factory RuleApplyConfirmation.fromJson(Map<String, dynamic> json) =>
      RuleApplyConfirmation(
        affectedCount: _int(json['affected_resource_count']),
        ruleCount: _int(json['rule_count']),
        activeRulesAboveCount: _int(json['active_rules_above_count']),
        autoCategorize: json['auto_categorize'] == true,
        aiModel: json['ai_model']?.toString(),
        estimatedAiCost: json['estimated_ai_cost'] is num
            ? (json['estimated_ai_cost'] as num).toDouble()
            : double.tryParse('${json['estimated_ai_cost'] ?? ''}'),
      );
}

/// One run of a rule from `GET /api/v1/rule_runs`.
class RuleRun {
  const RuleRun({
    required this.id,
    required this.status,
    this.ruleId,
    this.executionType,
    this.executedAt,
    this.transactionsQueued = 0,
    this.transactionsProcessed = 0,
    this.transactionsModified = 0,
    this.pendingJobsCount = 0,
    this.errorMessage,
  });

  final String id;
  final String? ruleId;

  /// `manual` or `scheduled`.
  final String? executionType;

  /// `pending`, `success` or `failed`.
  final String status;
  final DateTime? executedAt;
  final int transactionsQueued;
  final int transactionsProcessed;
  final int transactionsModified;
  final int pendingJobsCount;
  final String? errorMessage;

  factory RuleRun.fromJson(Map<String, dynamic> json) => RuleRun(
        id: json['id'].toString(),
        ruleId: json['rule_id']?.toString(),
        executionType: json['execution_type']?.toString(),
        status: json['status']?.toString() ?? '',
        executedAt: json['executed_at'] == null
            ? null
            : DateTime.tryParse(json['executed_at'].toString()),
        transactionsQueued: _int(json['transactions_queued']),
        transactionsProcessed: _int(json['transactions_processed']),
        transactionsModified: _int(json['transactions_modified']),
        pendingJobsCount: _int(json['pending_jobs_count']),
        errorMessage: json['error_message']?.toString(),
      );
}

List<T> _list<T>(dynamic raw, T Function(Map<String, dynamic>) fromJson) =>
    raw is List
        ? raw
            .whereType<Map>()
            .map((m) => fromJson(m.cast<String, dynamic>()))
            .toList()
        : <T>[];

int _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;
