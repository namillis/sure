/// A transaction rule from `GET /api/v1/rules` and `/api/v1/rules/:id`.
class Rule {
  const Rule({
    required this.id,
    this.name,
    this.resourceType = 'transaction',
    this.active = true,
    this.effectiveDate,
    this.conditions = const [],
    this.actions = const [],
  });

  final String id;

  /// Optional on the server; the web shows a summary when it's blank.
  final String? name;
  final String resourceType;
  final bool active;
  final DateTime? effectiveDate;

  /// Top-level conditions; compound ones carry [RuleCondition.subConditions].
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
        conditions: _list(json['conditions'], RuleCondition.fromJson),
        actions: _list(json['actions'], RuleAction.fromJson),
      );
}

class RuleCondition {
  const RuleCondition({
    required this.conditionType,
    required this.operator,
    this.value,
    this.subConditions = const [],
  });

  /// e.g. `transaction_name`, `transaction_amount`, or `compound`.
  final String conditionType;

  /// e.g. `like`, `>=`, `is_null`; `and` / `or` for compound conditions.
  final String operator;
  final String? value;
  final List<RuleCondition> subConditions;

  bool get isCompound => conditionType == 'compound';

  factory RuleCondition.fromJson(Map<String, dynamic> json) => RuleCondition(
        conditionType: json['condition_type']?.toString() ?? '',
        operator: json['operator']?.toString() ?? '',
        value: json['value']?.toString(),
        subConditions: _list(json['sub_conditions'], RuleCondition.fromJson),
      );
}

class RuleAction {
  const RuleAction({required this.actionType, this.value});

  /// e.g. `set_transaction_category`, `exclude_transaction`.
  final String actionType;
  final String? value;

  factory RuleAction.fromJson(Map<String, dynamic> json) => RuleAction(
        actionType: json['action_type']?.toString() ?? '',
        value: json['value']?.toString(),
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
