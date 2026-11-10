import '../utils/json_parsing.dart';

/// A buy/sell (or other investment activity) entry from `GET /api/v1/trades`.
class AccountTrade {
  final String id;
  final DateTime date;
  final String name;
  final String amount;
  final String currency;
  final String quantity;
  final String price;

  /// Server-provided activity label such as `Buy`, `Sell` or `Dividend`.
  final String? activityLabel;
  final String? ticker;
  final String? securityName;

  AccountTrade({
    required this.id,
    required this.date,
    required this.name,
    required this.amount,
    required this.currency,
    required this.quantity,
    required this.price,
    this.activityLabel,
    this.ticker,
    this.securityName,
  });

  factory AccountTrade.fromJson(Map<String, dynamic> json) {
    final securityJson = json['security'];
    final security = securityJson is Map<String, dynamic> ? securityJson : null;

    return AccountTrade(
      id: json['id'].toString(),
      date: JsonParsing.parseRequiredDateTime(json['date'], 'trade'),
      name: JsonParsing.parseString(json['name']) ?? '',
      amount: JsonParsing.parseRequiredString(json['amount'], 'trade amount'),
      currency:
          JsonParsing.parseRequiredString(json['currency'], 'trade currency'),
      quantity: JsonParsing.parseRequiredString(json['qty'], 'trade quantity'),
      price: JsonParsing.parseRequiredString(json['price'], 'trade price'),
      activityLabel: JsonParsing.parseString(json['investment_activity_label']),
      ticker: JsonParsing.parseString(security?['ticker']),
      securityName: JsonParsing.parseString(security?['name']),
    );
  }
}
