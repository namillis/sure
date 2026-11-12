import 'dart:convert';

class ToolCall {
  final String id;
  final String functionName;
  final Map<String, dynamic> functionArguments;
  final Map<String, dynamic>? functionResult;
  final DateTime createdAt;

  ToolCall({
    required this.id,
    required this.functionName,
    required this.functionArguments,
    this.functionResult,
    required this.createdAt,
  });

  /// A readable label for the tool the assistant used:
  /// "get_income_statement" -> "Income statement".
  String get displayName {
    var name = functionName.trim();
    for (final prefix in const ['get_', 'list_', 'fetch_', 'search_']) {
      if (name.startsWith(prefix) && name.length > prefix.length) {
        name = name.substring(prefix.length);
        break;
      }
    }
    final words = name.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    if (words.isEmpty) return functionName;
    return words[0].toUpperCase() + words.substring(1);
  }

  factory ToolCall.fromJson(Map<String, dynamic> json) {
    return ToolCall(
      id: json['id'].toString(),
      functionName: json['function_name'] as String,
      functionArguments: _parseJsonField(json['function_arguments']),
      functionResult: json['function_result'] != null
          ? _parseJsonField(json['function_result'])
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  static Map<String, dynamic> _parseJsonField(dynamic field) {
    if (field == null) return {};
    if (field is Map<String, dynamic>) return field;
    if (field is String) {
      try {
        final parsed = jsonDecode(field);
        return parsed is Map<String, dynamic> ? parsed : {};
      } catch (e) {
        return {};
      }
    }
    return {};
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'function_name': functionName,
      'function_arguments': functionArguments,
      'function_result': functionResult,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
