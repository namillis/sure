import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'imports_service.dart' show apiFailure;
import 'log_service.dart';

/// A security the account already holds, offered by the convert-to-trade
/// form.
class TradeConversionSecurity {
  const TradeConversionSecurity({
    required this.id,
    required this.ticker,
    this.name,
    this.currentPrice,
  });

  final String id;
  final String ticker;
  final String? name;

  /// Today's price, formatted by the server, or null.
  final String? currentPrice;

  static TradeConversionSecurity? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    String? text(Object? v) {
      final s = v?.toString().trim() ?? '';
      return s.isEmpty ? null : s;
    }

    return TradeConversionSecurity(
      id: id,
      ticker: text(json['ticker']) ?? '',
      name: text(json['name']),
      currentPrice: text(json['current_price']),
    );
  }
}

/// `GET /transactions/:id/convert_to_trade`: what the form needs.
class TradeConversionForm {
  const TradeConversionForm({
    required this.amount,
    required this.currency,
    required this.defaultLabel,
    required this.tickerSearchAvailable,
    required this.securities,
  });

  /// Unsigned, formatted by the server.
  final String amount;
  final String currency;

  /// `Buy` or `Sell`, or null.
  final String? defaultLabel;
  final bool tickerSearchAvailable;
  final List<TradeConversionSecurity> securities;

  factory TradeConversionForm.fromJson(Map<String, dynamic> json) {
    final defaults = json['defaults'];
    final label = defaults is Map
        ? defaults['investment_activity_label']?.toString()
        : null;
    final options = json['security_options'];
    return TradeConversionForm(
      amount: json['amount']?.toString() ?? '',
      currency: json['currency']?.toString() ?? '',
      defaultLabel: label == 'Buy' || label == 'Sell' ? label : null,
      tickerSearchAvailable: json['ticker_search_available'] == true,
      securities: options is List
          ? options
              .map(TradeConversionSecurity.fromJson)
              .whereType<TradeConversionSecurity>()
              .toList(growable: false)
          : const [],
    );
  }
}

/// Client for Sure+ `transactions.convert_to_trade`. Returns the app's
/// `{'success': bool, ...}` maps; failures carry the server's `'code'`
/// (`select_security`, `enter_qty_or_price`, ...) and `'error'` message.
class TradeConversionService {
  static const Duration _timeout = Duration(seconds: 30);

  final http.Client _client;
  final bool _ownsClient;

  TradeConversionService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void close() {
    if (_ownsClient) _client.close();
  }

  Uri _uri(String transactionId) => Uri.parse('${ApiConfig.baseUrl}'
      '/api/v1/transactions/${Uri.encodeComponent(transactionId)}/convert_to_trade');

  /// `'form'` holds a [TradeConversionForm].
  Future<Map<String, dynamic>> load({
    required String accessToken,
    required String transactionId,
  }) async {
    try {
      final response = await _client
          .get(_uri(transactionId),
              headers: ApiConfig.getAuthHeaders(accessToken))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'form': TradeConversionForm.fromJson(
              jsonDecode(response.body) as Map<String, dynamic>),
        };
      }
      return apiFailure(response, 'Unable to load the trade form');
    } catch (e) {
      return _error('load', e, 'Unable to load the trade form.');
    }
  }

  /// Sends exactly one of [securityId] or [customTicker], and [qty] and/or
  /// [price] as canonical decimals.
  Future<Map<String, dynamic>> convert({
    required String accessToken,
    required String transactionId,
    required String label,
    String? securityId,
    String? customTicker,
    String? qty,
    String? price,
  }) async {
    try {
      final response = await _client
          .post(
            _uri(transactionId),
            headers: {
              ...ApiConfig.getAuthHeaders(accessToken),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'trade': {
                if (securityId != null) 'security_id': securityId,
                if (securityId == null && customTicker != null)
                  'custom_ticker': customTicker,
                if (qty != null) 'qty': qty,
                if (price != null) 'price': price,
                'investment_activity_label': label,
              },
            }),
          )
          .timeout(_timeout);
      if (response.statusCode == 201 || response.statusCode == 200) {
        return {'success': true};
      }
      return apiFailure(response, 'The transaction could not be converted');
    } catch (e) {
      return _error('convert', e, 'Unable to convert. Please try again later.');
    }
  }

  Map<String, dynamic> _error(String operation, Object error, String message) {
    LogService.instance.error(
        'TradeConversionService', '$operation failed with ${error.runtimeType}');
    return {'success': false, 'error': message};
  }
}
