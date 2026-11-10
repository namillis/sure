import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/account_trade.dart';
import '../models/trade_security.dart';
import 'api_config.dart';
import 'log_service.dart';
import 'transactions_service.dart';

/// Buy/sell trade writes (`/api/v1/trades`) and the family's known
/// securities (`GET /api/v1/securities`).
class TradesService {
  final http.Client _client;
  final bool _ownsClient;

  TradesService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void close() {
    if (_ownsClient) _client.close();
  }

  Map<String, String> _jsonHeaders(String token) => {
        ...ApiConfig.getAuthHeaders(token),
        'Content-Type': 'application/json',
      };

  /// Records a buy or sell. [type] is `buy` or `sell`; [qty], [price] and
  /// [fee] are positive canonical decimal strings; [date] is `yyyy-MM-dd`.
  /// Give [securityId] for a known security, otherwise [ticker] (the server
  /// resolves it, optionally as `TICKER|MIC`).
  Future<Map<String, dynamic>> createTrade({
    required String accessToken,
    required String accountId,
    required String type,
    required String date,
    required String qty,
    required String price,
    String? fee,
    String? securityId,
    String? ticker,
    String? currency,
  }) {
    final body = {
      'trade': {
        'account_id': accountId,
        'type': type,
        'date': date,
        'qty': qty,
        'price': price,
        if (fee != null) 'fee': fee,
        if (securityId != null)
          'security_id': securityId
        else if (ticker != null)
          'ticker': ticker,
        if (currency != null) 'currency': currency,
      },
    };
    return _send(
      () => _client.post(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/trades'),
        headers: _jsonHeaders(accessToken),
        body: jsonEncode(body),
      ),
      operation: 'createTrade',
      fallback: 'Failed to add trade',
    );
  }

  /// Changes a buy/sell. The server recomputes the amount as qty × price and
  /// does not accept a fee or a different security on update.
  Future<Map<String, dynamic>> updateTrade({
    required String accessToken,
    required String tradeId,
    required String type,
    required String date,
    required String qty,
    required String price,
  }) {
    final body = {
      'trade': {'type': type, 'date': date, 'qty': qty, 'price': price},
    };
    return _send(
      () => _client.patch(
        Uri.parse(
            '${ApiConfig.baseUrl}/api/v1/trades/${Uri.encodeComponent(tradeId)}'),
        headers: _jsonHeaders(accessToken),
        body: jsonEncode(body),
      ),
      operation: 'updateTrade',
      fallback: 'Failed to update trade',
    );
  }

  Future<Map<String, dynamic>> deleteTrade({
    required String accessToken,
    required String tradeId,
  }) {
    return _send(
      () => _client.delete(
        Uri.parse(
            '${ApiConfig.baseUrl}/api/v1/trades/${Uri.encodeComponent(tradeId)}'),
        headers: ApiConfig.getAuthHeaders(accessToken),
      ),
      operation: 'deleteTrade',
      fallback: 'Failed to delete trade',
      parseTrade: false,
    );
  }

  /// Securities the family already holds or traded, for ticker suggestions.
  /// The API has no free-text search (only an exact `ticker` filter), so the
  /// form filters this list on the device.
  ///
  /// shortcut: first 100 only; page through `pagination` if families hit it.
  Future<Map<String, dynamic>> getSecurities({
    required String accessToken,
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/securities')
        .replace(queryParameters: {'per_page': '100'});
    try {
      final response = await _client
          .get(url, headers: ApiConfig.getAuthHeaders(accessToken))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          'success': true,
          'securities': (data['securities'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(TradeSecurity.fromJson)
              .where((s) => s.ticker.isNotEmpty)
              .toList(),
        };
      }
      return _failure(response, 'Failed to load securities');
    } catch (e) {
      _log('getSecurities', e);
      return {'success': false, 'error': 'Unable to load securities.'};
    }
  }

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request, {
    required String operation,
    required String fallback,
    bool parseTrade = true,
  }) async {
    try {
      final response = await request().timeout(const Duration(seconds: 30));
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          if (parseTrade)
            'trade': AccountTrade.fromJson(
                jsonDecode(response.body) as Map<String, dynamic>),
        };
      }
      return _failure(response, fallback);
    } catch (e) {
      _log(operation, e);
      return {'success': false, 'error': '$fallback. Please try again.'};
    }
  }

  Map<String, dynamic> _failure(http.Response response, String fallback) {
    if (response.statusCode == 401) {
      return {'success': false, 'error': 'unauthorized'};
    }
    return {
      'success': false,
      'error': TransactionsService.errorMessageFromResponseBody(
        response.body,
        fallback: fallback,
      ),
    };
  }

  void _log(String operation, Object error) {
    LogService.instance.error(
      'TradesService',
      '$operation failed with ${error.runtimeType}',
    );
  }
}
