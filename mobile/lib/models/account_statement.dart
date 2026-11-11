import '../utils/json_parsing.dart';

/// One statement from `/api/v1/account_statements`.
class AccountStatement {
  const AccountStatement({
    required this.id,
    required this.filename,
    this.byteSize,
    this.reviewStatus,
    this.periodStart,
    this.periodEnd,
    this.accountId,
    this.accountName,
    this.createdAt,
  });

  final String id;
  final String filename;
  final int? byteSize;
  final String? reviewStatus;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final String? accountId;
  final String? accountName;
  final DateTime? createdAt;

  factory AccountStatement.fromJson(Map<String, dynamic> json) {
    final account = json['account'] is Map<String, dynamic>
        ? json['account'] as Map<String, dynamic>
        : null;
    return AccountStatement(
      id: json['id'].toString(),
      filename: JsonParsing.parseString(json['filename']) ?? '',
      byteSize: JsonParsing.parseInt(json['byte_size']),
      reviewStatus: JsonParsing.parseString(json['review_status']),
      periodStart: JsonParsing.parseDateTime(json['period_start_on']),
      periodEnd: JsonParsing.parseDateTime(json['period_end_on']),
      accountId: JsonParsing.parseString(account?['id']),
      accountName: JsonParsing.parseString(account?['name']),
      createdAt: JsonParsing.parseDateTime(json['created_at']),
    );
  }
}
