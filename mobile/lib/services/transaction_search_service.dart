import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/activity_filters.dart';
import '../models/activity_transaction.dart';
import '../utils/json_parsing.dart';
import 'api_config.dart';
import 'log_service.dart';

/// Server-side search across every account for the Activity tab:
/// `GET /api/v1/transactions` with search, date, account, category, tag and
/// type filters, plus the single-field category update bulk categorize uses.
class TransactionSearchService {
  /// The API caps `per_page` at 100.
  static const int maxPerPage = 100;

  final http.Client _client;

  TransactionSearchService({http.Client? client})
      : _client = client ?? http.Client();

  /// One page of transactions matching [filters], newest first.
  ///
  /// On success returns `transactions` (`List<ActivityTransaction>`), `page`,
  /// `totalPages` and `totalCount`.
  Future<Map<String, dynamic>> search({
    required String accessToken,
    required ActivityFilters filters,
    int page = 1,
    int perPage = 50,
    DateTime? now,
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/transactions').replace(
      queryParameters: {
        ...filters.queryParameters(now ?? DateTime.now()),
        'page': page.toString(),
        'per_page': perPage.clamp(1, maxPerPage).toString(),
      },
    );

    try {
      final response = await _client
          .get(url, headers: ApiConfig.getAuthHeaders(accessToken))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rows = (data['transactions'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ActivityTransaction.fromJson)
            .toList();
        final pagination = data['pagination'] as Map<String, dynamic>?;
        return {
          'success': true,
          'transactions': rows,
          'page': JsonParsing.parseInt(pagination?['page']) ?? page,
          'totalPages':
              JsonParsing.parseInt(pagination?['total_pages']) ?? page,
          'totalCount':
              JsonParsing.parseInt(pagination?['total_count']) ?? rows.length,
        };
      }

      return _failure(response, 'Failed to load transactions');
    } catch (e) {
      _logFailure('search', e);
      return {
        'success': false,
        'error': 'Unable to load transactions. Please try again later.',
      };
    }
  }

  /// Sets one transaction's category. On success returns the updated row as
  /// `transaction` (`ActivityTransaction`).
  Future<Map<String, dynamic>> updateCategory({
    required String accessToken,
    required String transactionId,
    required String categoryId,
  }) async {
    final url = Uri.parse(
      '${ApiConfig.baseUrl}/api/v1/transactions/'
      '${Uri.encodeComponent(transactionId)}',
    );

    try {
      final response = await _client
          .patch(
            url,
            headers: {
              ...ApiConfig.getAuthHeaders(accessToken),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'transaction': {'category_id': categoryId},
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return {
          'success': true,
          'transaction': ActivityTransaction.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>,
          ),
        };
      }

      return _failure(response, 'Failed to update transaction');
    } catch (e) {
      _logFailure('updateCategory', e);
      return {
        'success': false,
        'error': 'Unable to update transaction. Please try again later.',
      };
    }
  }

  Map<String, dynamic> _failure(http.Response response, String fallback) {
    if (response.statusCode == 401) {
      return {'success': false, 'error': 'unauthorized'};
    }
    var message = fallback;
    try {
      final data = jsonDecode(response.body);
      if (data is Map && data['message'] is String) {
        message = data['message'] as String;
      }
    } catch (_) {
      // Non-JSON error bodies keep the fallback message.
    }
    return {'success': false, 'error': message};
  }

  void _logFailure(String operation, Object error) {
    LogService.instance.error(
      'TransactionSearchService',
      '$operation failed with ${error.runtimeType}',
    );
  }
}
