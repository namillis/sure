/// One insight from `GET /api/v1/insights` (a web preview feature).
class Insight {
  const Insight({
    required this.id,
    required this.title,
    required this.body,
    this.type,
    this.priority = 'low',
    this.status = 'active',
    this.generatedAt,
  });

  final String id;
  final String title;
  final String body;
  final String? type;

  /// `high`, `medium` or `low`.
  final String priority;

  /// `active` or `read`; the index returns only these two.
  final String status;
  final DateTime? generatedAt;

  factory Insight.fromJson(Map<String, dynamic> json) => Insight(
        id: json['id'].toString(),
        title: json['title']?.toString() ?? '',
        body: json['body']?.toString() ?? '',
        type: json['type']?.toString(),
        priority: json['priority']?.toString() ?? 'low',
        status: json['status']?.toString() ?? 'active',
        generatedAt: json['generated_at'] == null
            ? null
            : DateTime.tryParse(json['generated_at'].toString()),
      );
}
