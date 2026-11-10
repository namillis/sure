import '../utils/json_parsing.dart';

/// One sync run from `POST /api/v1/sync` or `GET /api/v1/syncs/...`.
///
/// Server statuses: `pending`, `syncing`, `completed`, `failed`, `stale`.
class FamilySync {
  final String id;
  final String status;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final DateTime? failedAt;

  /// `error.message` from the server; only set for failed or stale syncs.
  final String? errorMessage;

  const FamilySync({
    required this.id,
    required this.status,
    this.createdAt,
    this.completedAt,
    this.failedAt,
    this.errorMessage,
  });

  /// Mirrors Sync#in_progress? (pending or syncing).
  bool get inProgress => status == 'pending' || status == 'syncing';

  /// Mirrors Sync#terminal? (completed, failed or stale).
  bool get terminal => !inProgress;

  bool get completed => status == 'completed';

  bool get failed => status == 'failed' || status == 'stale';

  factory FamilySync.fromJson(Map<String, dynamic> json) {
    final error = json['error'];
    return FamilySync(
      id: json['id'].toString(),
      status: JsonParsing.parseString(json['status']) ?? 'pending',
      createdAt: _date(json['created_at']),
      completedAt: _date(json['completed_at']),
      failedAt: _date(json['failed_at']),
      errorMessage: error is Map<String, dynamic>
          ? JsonParsing.parseString(error['message'])
          : null,
    );
  }

  static DateTime? _date(dynamic value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}
