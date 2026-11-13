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

  /// Top-level conditions; compound ones carry [RuleCondition.subConditions].
  /// The server ANDs top-level conditions (no rule-wide any/all switch).
  final List<RuleCondition> conditions;
  final List<RuleAction> actions;

  bool get hasName => (name?.trim() ?? '').isNotEmpty;

  factory Rule.fromJson(Map<String, dynamic> json) => Rule(
        id: json['id'].toString(),
        name: json['name']?.toString(),
        resourceType: json['resource_type']?.toString() ?? 'transaction',
        active: json['active'] != false,
        effectiveDate: json['effective_date'] == null
            ? null
            : DateTime.tryParse(json['effective_date'].toString()),
        stopProcessing: json['stop_processing'] == true,
        ruleGroupId: json['rule_group_id']?.toString(),
        conditions: _list(json['conditions'], RuleCondition.fromJson),
        actions: _list(json['actions'], RuleAction.fromJson),
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
  const RuleAction({this.id, required this.actionType, this.value});

  /// The saved action's id; null for one the editor added.
  final String? id;

  /// e.g. `set_transaction_category`, `exclude_transaction`.
  final String actionType;

  /// A single id or text; tag ids comma-separated; a JSON config for
  /// `split_transaction`.
  final String? value;

  factory RuleAction.fromJson(Map<String, dynamic> json) => RuleAction(
        id: json['id']?.toString(),
        actionType: json['action_type']?.toString() ?? '',
        value: json['value']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'action_type': actionType,
        'value': value,
      };
}

/// What `POST /api/v1/rules/:id/apply` without `confirm` reports (422
/// `confirmation_required`): the same facts the web's confirm dialog shows.
class RuleApplyConfirmation {
  const RuleApplyConfirmation({
    required this.affectedCount,
    this.activeRulesAboveCount = 0,
    this.autoCategorize = false,
    this.aiModel,
    this.estimatedAiCost,
  });

  final int affectedCount;
  final int activeRulesAboveCount;
  final bool autoCategorize;
  final String? aiModel;

  /// US dollars, or null when the server can't estimate it.
  final double? estimatedAiCost;

  factory RuleApplyConfirmation.fromJson(Map<String, dynamic> json) =>
      RuleApplyConfirmation(
        affectedCount: _int(json['affected_resource_count']),
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
