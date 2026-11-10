import '../utils/json_parsing.dart';

/// A security already known to the family, from `GET /api/v1/securities`.
class TradeSecurity {
  final String id;
  final String ticker;
  final String? name;
  final String? exchangeOperatingMic;

  const TradeSecurity({
    required this.id,
    required this.ticker,
    this.name,
    this.exchangeOperatingMic,
  });

  factory TradeSecurity.fromJson(Map<String, dynamic> json) => TradeSecurity(
        id: json['id'].toString(),
        ticker: JsonParsing.parseString(json['ticker']) ?? '',
        name: JsonParsing.parseString(json['name']),
        exchangeOperatingMic:
            JsonParsing.parseString(json['exchange_operating_mic']),
      );

  /// True when [query] is a prefix of the ticker or appears in the name.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return ticker.toLowerCase().startsWith(q) ||
        (name?.toLowerCase().contains(q) ?? false);
  }
}
