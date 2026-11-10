import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/recurring_transaction.dart';
import 'api_config.dart';
import 'log_service.dart';

/// Client for `/api/v1/recurring_transactions`. Returns the app's
/// `{'success': bool, ...}` maps, with `'error': 'unauthorized'` on 401.
class RecurringTransactionsService {
  static const int _perPage = 100;
  static const int _maxPages = 20;
  static const Duration _timeout = Duration(seconds: 30);

  final http.Client _client;
  final bool _ownsClient;

  RecurringTransactionsService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void close() {
    if (_ownsClient) _client.close();
  }

  Uri _collection([Map<String, String>? query]) =>
      Uri.parse('${ApiConfig.baseUrl}/api/v1/recurring_transactions')
          .replace(queryParameters: query);

  Uri _member(String id) => Uri.parse(
      '${ApiConfig.baseUrl}/api/v1/recurring_transactions/${Uri.encodeComponent(id)}');

  /// Every recurring transaction the user can see (all statuses), walking
  /// pages of 100. `'recurring_transactions'` holds a
  /// `List<RecurringTransaction>`.
  Future<Map<String, dynamic>> getAll({required String accessToken}) async {
    final items = <RecurringTransaction>[];
    try {
      var page = 1;
      var totalPages = 1;
      while (page <= totalPages && page <= _maxPages) {
        final response = await _client
            .get(
              _collection({
                'page': page.toString(),
                'per_page': _perPage.toString(),
              }),
              headers: ApiConfig.getAuthHeaders(accessToken),
            )
            .timeout(_timeout);
        if (response.statusCode != 200) {
          return _failure(response, 'Failed to load recurring transactions');
        }
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        items.addAll((data['recurring_transactions'] as List<dynamic>? ?? [])
            .map((j) => RecurringTransaction.fromJson(j as Map<String, dynamic>)));
        final pagination = data['pagination'] as Map<String, dynamic>?;
        totalPages = (pagination?['total_pages'] as num?)?.toInt() ?? 1;
        page++;
      }
      return {'success': true, 'recurring_transactions': items};
    } catch (e) {
      _log('getAll', e);
      return {
        'success': false,
        'error': 'Unable to load recurring transactions. Please try again later.',
      };
    }
  }

  /// Creates one from [attributes] (keys as the API's create params:
  /// name, amount, currency, account_id, expected_day_of_month,
  /// last_occurrence_date, next_expected_date, status, autopay, payment_url,
  /// notes).
  Future<Map<String, dynamic>> create({
    required String accessToken,
    required Map<String, dynamic> attributes,
  }) =>
      _write(
        'create',
        () => _client.post(
          _collection(),
          headers: ApiConfig.getAuthHeaders(accessToken),
          body: jsonEncode({'recurring_transaction': attributes}),
        ),
        expected: 201,
      );

  /// Updates [id]. The API accepts only status, expected_day_of_month,
  /// next_expected_date, payment_url, autopay and notes here.
  Future<Map<String, dynamic>> update({
    required String accessToken,
    required String id,
    required Map<String, dynamic> attributes,
  }) =>
      _write(
        'update',
        () => _client.patch(
          _member(id),
          headers: ApiConfig.getAuthHeaders(accessToken),
          body: jsonEncode({'recurring_transaction': attributes}),
        ),
        expected: 200,
      );

  Future<Map<String, dynamic>> delete({
    required String accessToken,
    required String id,
  }) async {
    try {
      final response = await _client
          .delete(_member(id), headers: ApiConfig.getAuthHeaders(accessToken))
          .timeout(_timeout);
      if (response.statusCode == 200 || response.statusCode == 204) {
        return {'success': true};
      }
      return _failure(response, 'Failed to delete recurring transaction');
    } catch (e) {
      _log('delete', e);
      return {
        'success': false,
        'error': 'Unable to delete. Please try again later.',
      };
    }
  }

  Future<Map<String, dynamic>> _write(
    String operation,
    Future<http.Response> Function() send, {
    required int expected,
  }) async {
    try {
      final response = await send().timeout(_timeout);
      if (response.statusCode == expected) {
        return {
          'success': true,
          'recurring_transaction': RecurringTransaction.fromJson(
              jsonDecode(response.body) as Map<String, dynamic>),
        };
      }
      return _failure(response, 'Failed to save recurring transaction');
    } catch (e) {
      _log(operation, e);
      return {
        'success': false,
        'error': 'Unable to save. Please try again later.',
      };
    }
  }

  /// 401 is `unauthorized`; otherwise the server's validation messages when
  /// it sent any, else [fallback].
  Map<String, dynamic> _failure(http.Response response, String fallback) {
    if (response.statusCode == 401) {
      return {'success': false, 'error': 'unauthorized'};
    }
    var message = fallback;
    try {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) {
        final errors = data['errors'];
        if (errors is List && errors.isNotEmpty) {
          message = errors.join('\n');
        } else if (data['message'] is String) {
          message = data['message'] as String;
        }
      }
    } catch (_) {}
    return {'success': false, 'error': message, 'status': response.statusCode};
  }

  void _log(String operation, Object error) {
    LogService.instance.error(
      'RecurringTransactionsService',
      '$operation failed with ${error.runtimeType}',
    );
  }
}
