import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'log_service.dart';
import 'transactions_service.dart';

/// Records a balance update ("valuation") with `POST /api/v1/valuations`.
///
/// The server reconciles the account to [amount] on [date] (replacing any
/// valuation already on that date) and queues an account sync.
class ValuationsService {
  final http.Client _client;
  final bool _ownsClient;

  ValuationsService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void close() {
    if (_ownsClient) _client.close();
  }

  /// [amount] is a canonical decimal string (see `AmountParser.canonicalize`)
  /// and [date] is `yyyy-MM-dd`. Returns `valuation` (the decoded response)
  /// on success.
  Future<Map<String, dynamic>> createValuation({
    required String accessToken,
    required String accountId,
    required String amount,
    required String date,
    String? notes,
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/valuations');
    final body = {
      'valuation': {
        'account_id': accountId,
        'amount': amount,
        'date': date,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    };

    try {
      final response = await _client
          .post(
            url,
            headers: {
              ...ApiConfig.getAuthHeaders(accessToken),
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'valuation': jsonDecode(response.body) as Map<String, dynamic>,
        };
      }
      if (response.statusCode == 401) {
        return {'success': false, 'error': 'unauthorized'};
      }
      return {
        'success': false,
        'error': TransactionsService.errorMessageFromResponseBody(
          response.body,
          fallback: 'Failed to update balance',
        ),
      };
    } catch (e) {
      LogService.instance.error(
        'ValuationsService',
        'createValuation failed with ${e.runtimeType}',
      );
      return {'success': false, 'error': 'Unable to update balance.'};
    }
  }
}
