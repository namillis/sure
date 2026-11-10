/// One parent category row of `GET /api/v1/spending_vs_normal`. Amounts are
/// decimal strings in the family currency on the wire, parsed here.
class SpendingCategory {
  const SpendingCategory({
    required this.id,
    required this.name,
    required this.total,
    this.color,
    this.normal,
    this.change,
    this.ratio,
  });

  final String id;
  final String name;
  final String? color;
  final double total;

  /// Null when there is not enough history to know what is normal.
  final double? normal;
  final double? change;

  /// Fractional change against normal (0.32 = 32% more); null without a
  /// positive normal.
  final double? ratio;

  factory SpendingCategory.fromJson(Map<String, dynamic> json) =>
      SpendingCategory(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        color: json['color']?.toString(),
        total: _decimal(json['total']) ?? 0,
        normal: _decimal(json['normal']),
        change: _decimal(json['change']),
        ratio: _decimal(json['ratio']),
      );
}

/// Net spending per category this period against each category's normal.
class SpendingVsNormal {
  const SpendingVsNormal({
    required this.currency,
    required this.comparable,
    required this.inProgress,
    required this.total,
    required this.categories,
    this.normalTotal,
  });

  final String currency;

  /// False when the family has too little history for a normal.
  final bool comparable;

  /// The period is unfinished and counts spending so far.
  final bool inProgress;
  final double total;
  final double? normalTotal;

  /// Largest spending first, as the server sorts them.
  final List<SpendingCategory> categories;

  factory SpendingVsNormal.fromJson(Map<String, dynamic> json) =>
      SpendingVsNormal(
        currency: json['currency']?.toString() ?? 'USD',
        comparable: json['comparable'] == true,
        inProgress: json['in_progress'] == true,
        total: _decimal(json['total']) ?? 0,
        normalTotal: _decimal(json['normal_total']),
        categories: (json['categories'] as List<dynamic>? ?? [])
            .map((c) => SpendingCategory.fromJson(c as Map<String, dynamic>))
            .toList(),
      );

  /// Overall change against normal as a fraction, or null without a normal.
  double? get ratio {
    final normal = normalTotal;
    if (normal == null || normal <= 0) return null;
    return (total - normal) / normal;
  }

  /// Up to [count] categories furthest above normal by amount (at least one
  /// unit over), so a tiny category doubling does not outrank a big one.
  List<SpendingCategory> topAboveNormal([int count = 3]) {
    final above = categories
        .where((c) => c.change != null && c.change! >= 1)
        .toList()
      ..sort((a, b) => b.change!.compareTo(a.change!));
    return above.take(count).toList();
  }
}

double? _decimal(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
