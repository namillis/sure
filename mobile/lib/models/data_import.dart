import '../utils/json_parsing.dart';

/// One import from `/api/v1/imports` (index item or show payload).
class DataImport {
  const DataImport({
    required this.id,
    required this.type,
    required this.status,
    this.createdAt,
    this.accountId,
    this.rowsCount,
    this.validRowsCount,
    this.invalidRowsCount,
    this.error,
    this.terminal = false,
  });

  final String id;
  final String type;

  /// pending, importing, complete, failed, reverting, revert_failed.
  final String status;
  final DateTime? createdAt;
  final String? accountId;
  final int? rowsCount;

  /// Only the show payload carries these.
  final int? validRowsCount;
  final int? invalidRowsCount;
  final String? error;

  /// The server's `status_detail.terminal`.
  final bool terminal;

  factory DataImport.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] is Map<String, dynamic>
        ? json['stats'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final detail = json['status_detail'] is Map<String, dynamic>
        ? json['status_detail'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return DataImport(
      id: json['id'].toString(),
      type: JsonParsing.parseString(json['type']) ?? 'Import',
      status: JsonParsing.parseString(json['status']) ?? 'pending',
      createdAt: JsonParsing.parseDateTime(json['created_at']),
      accountId: JsonParsing.parseString(json['account_id']),
      rowsCount: JsonParsing.parseInt(json['rows_count'] ?? stats['rows_count']),
      validRowsCount: JsonParsing.parseInt(stats['valid_rows_count']),
      invalidRowsCount: JsonParsing.parseInt(stats['invalid_rows_count']),
      error: JsonParsing.parseString(json['error']),
      terminal: detail['terminal'] == true,
    );
  }

  /// The server is still working on it, so polling can make progress.
  bool get inProgress => status == 'importing' || status == 'reverting';

  bool get isComplete => status == 'complete';

  bool get isFailed => status == 'failed' || status == 'revert_failed';
}

/// One parsed row from `GET /api/v1/imports/:id/rows`.
class DataImportRow {
  const DataImportRow({
    required this.rowNumber,
    required this.valid,
    this.errors = const [],
    this.date,
    this.amount,
    this.name,
    this.category,
    this.tags,
    this.notes,
  });

  final int rowNumber;
  final bool valid;
  final List<String> errors;
  final String? date;
  final String? amount;
  final String? name;
  final String? category;
  final String? tags;
  final String? notes;

  factory DataImportRow.fromJson(Map<String, dynamic> json) {
    final fields = json['fields'] is Map<String, dynamic>
        ? json['fields'] as Map<String, dynamic>
        : const <String, dynamic>{};
    String? field(String key) {
      final value = JsonParsing.parseString(fields[key]);
      return (value == null || value.isEmpty) ? null : value;
    }

    return DataImportRow(
      rowNumber: JsonParsing.parseInt(json['row_number']) ?? 0,
      valid: json['valid'] != false,
      errors: (json['errors'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      date: field('date'),
      amount: field('amount'),
      name: field('name'),
      category: field('category'),
      tags: field('tags'),
      notes: field('notes'),
    );
  }
}

/// The `data` of `POST /api/v1/imports/preflight` for a CSV import.
class ImportPreflight {
  const ImportPreflight({
    required this.valid,
    this.headers = const [],
    this.requiredHeaders = const [],
    this.missingRequiredHeaders = const [],
    this.errors = const [],
    this.warnings = const [],
    this.rowsCount = 0,
  });

  final bool valid;
  final List<String> headers;
  final List<String> requiredHeaders;
  final List<String> missingRequiredHeaders;

  /// The `message` of each `{code, message}` error.
  final List<String> errors;
  final List<String> warnings;
  final int rowsCount;

  factory ImportPreflight.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? value) => (value as List<dynamic>? ?? const [])
        .map((e) => e is Map ? (e['message'] ?? e['code']).toString() : e.toString())
        .toList();
    final stats = json['stats'] is Map<String, dynamic>
        ? json['stats'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return ImportPreflight(
      valid: json['valid'] == true,
      headers: strings(json['headers']),
      requiredHeaders: strings(json['required_headers']),
      missingRequiredHeaders: strings(json['missing_required_headers']),
      errors: strings(json['errors']),
      warnings: strings(json['warnings']),
      rowsCount: JsonParsing.parseInt(stats['rows_count']) ?? 0,
    );
  }
}
