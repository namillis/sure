/// `GET /api/v1/settings/ai` (Sure+ `settings.ai`, admins only): the AI
/// prompt overrides and the Bayes classifier's settings.
class AiSettings {
  const AiSettings({
    this.aiAvailable = false,
    this.aiEnabled = false,
    required this.promptMaxLength,
    this.prompts = const [],
    required this.classifier,
  });

  final bool aiAvailable;
  final bool aiEnabled;
  final int promptMaxLength;
  final List<AiPrompt> prompts;
  final ClassifierSettings classifier;

  factory AiSettings.fromJson(Map<String, dynamic> json) {
    final body = json['ai_settings'] is Map<String, dynamic>
        ? json['ai_settings'] as Map<String, dynamic>
        : json;
    final prompts = body['prompts'];
    final classifier = body['classifier'];
    return AiSettings(
      aiAvailable: body['ai_available'] == true,
      aiEnabled: body['ai_enabled'] == true,
      promptMaxLength: (body['prompt_max_length'] as num?)?.toInt() ?? 20000,
      prompts: prompts is List
          ? prompts
              .whereType<Map<String, dynamic>>()
              .map(AiPrompt.fromJson)
              .toList()
          : const [],
      classifier: ClassifierSettings.fromJson(
          classifier is Map<String, dynamic> ? classifier : const {}),
    );
  }
}

class AiPrompt {
  const AiPrompt({
    required this.key,
    this.value,
    this.defaultText = '',
    this.custom = false,
    this.formatRisk = false,
    this.formatRiskKey,
  });

  /// `chat_system`, `categorizer_openai`, … (`Family::AiPromptable::KEYS`).
  final String key;

  /// The override, or null when the default is used.
  final String? value;
  final String defaultText;
  final bool custom;

  /// True when the override dropped the JSON example the response parser
  /// relies on; [formatRiskKey] names that example's key.
  final bool formatRisk;
  final String? formatRiskKey;

  /// What the prompt sends today: the override, else the default.
  String get effective => custom && value != null ? value! : defaultText;

  factory AiPrompt.fromJson(Map<String, dynamic> json) => AiPrompt(
        key: json['key'].toString(),
        value: json['value']?.toString(),
        defaultText: json['default']?.toString() ?? '',
        custom: json['custom'] == true,
        formatRisk: json['format_risk'] == true,
        formatRiskKey: json['format_risk_key']?.toString(),
      );
}

class ClassifierRule {
  const ClassifierRule({
    required this.actionType,
    required this.name,
    this.exists = false,
    this.active = false,
  });

  /// `bayes_categorize` or `fill_similar_merchants`.
  final String actionType;
  final String name;
  final bool exists;
  final bool active;

  factory ClassifierRule.fromJson(Map<String, dynamic> json) => ClassifierRule(
        actionType: json['action_type'].toString(),
        name: json['name']?.toString() ?? '',
        exists: json['exists'] == true,
        active: json['active'] == true,
      );
}

/// A numeric setting's allowed range (inclusive).
class SettingRange {
  const SettingRange(this.min, this.max);

  final num min;
  final num max;
}

class ClassifierSettings {
  const ClassifierSettings({
    this.settings = const {},
    this.defaults = const {},
    this.ranges = const {},
    this.choices = const {},
    this.rules = const [],
  });

  /// Current values, keyed like `Family::BayesSettings::DEFAULTS`.
  final Map<String, dynamic> settings;
  final Map<String, dynamic> defaults;
  final Map<String, SettingRange> ranges;
  final Map<String, List<String>> choices;
  final List<ClassifierRule> rules;

  ClassifierRule? rule(String actionType) {
    for (final r in rules) {
      if (r.actionType == actionType) return r;
    }
    return null;
  }

  factory ClassifierSettings.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> map(Object? v) =>
        v is Map<String, dynamic> ? v : const {};
    final ranges = <String, SettingRange>{};
    map(json['ranges']).forEach((key, value) {
      if (value is Map && value['min'] is num && value['max'] is num) {
        ranges[key] = SettingRange(value['min'] as num, value['max'] as num);
      }
    });
    final choices = <String, List<String>>{};
    map(json['choices']).forEach((key, value) {
      if (value is List) choices[key] = value.map((e) => e.toString()).toList();
    });
    final rules = json['rules'];
    return ClassifierSettings(
      settings: map(json['settings']),
      defaults: map(json['defaults']),
      ranges: ranges,
      choices: choices,
      rules: rules is List
          ? rules
              .whereType<Map<String, dynamic>>()
              .map(ClassifierRule.fromJson)
              .toList()
          : const [],
    );
  }
}

/// `GET /api/v1/settings/ai/usage` (last 30 days by default). Costs are in
/// USD; [totalCost] is the server's formatted string and [totalCostAmount]
/// the unrounded decimal, since most requests cost under a cent.
class AiUsage {
  const AiUsage({
    required this.totalCost,
    this.totalCostAmount,
    this.totalRequests = 0,
    this.byModel = const [],
  });

  final String totalCost;
  final String? totalCostAmount;
  final int totalRequests;
  final List<AiModelUsage> byModel;

  factory AiUsage.fromJson(Map<String, dynamic> json) {
    final body = json['llm_usage'] is Map<String, dynamic>
        ? json['llm_usage'] as Map<String, dynamic>
        : json;
    final models = body['by_model'];
    return AiUsage(
      totalCost: body['total_cost']?.toString() ?? '',
      totalCostAmount: body['total_cost_amount']?.toString(),
      totalRequests: (body['total_requests'] as num?)?.toInt() ?? 0,
      byModel: models is List
          ? models
              .whereType<Map<String, dynamic>>()
              .map(AiModelUsage.fromJson)
              .toList()
          : const [],
    );
  }
}

class AiModelUsage {
  const AiModelUsage({
    required this.model,
    this.totalRequests = 0,
    this.totalTokens = 0,
    required this.cost,
  });

  final String model;
  final int totalRequests;
  final int totalTokens;

  /// Formatted, e.g. `$0.0123`.
  final String cost;

  factory AiModelUsage.fromJson(Map<String, dynamic> json) => AiModelUsage(
        model: json['model']?.toString() ?? '',
        totalRequests: (json['total_requests'] as num?)?.toInt() ?? 0,
        totalTokens: (json['total_tokens'] as num?)?.toInt() ?? 0,
        cost: json['cost']?.toString() ?? '',
      );
}
