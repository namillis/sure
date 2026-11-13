import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/account.dart';
import 'api_config.dart';
import 'log_service.dart';
import 'response_list_parser.dart';

class AccountsService {
  AccountsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// The page size older versions fetched; a cache of exactly this many
  /// accounts may be a truncated first page.
  static const int legacyPageSize = 25;

  /// The API caps `per_page` at 100.
  static const int maxPerPage = 100;

  /// Upper bound on the pages [getAllAccounts] follows, so a bad `total_pages`
  /// cannot loop forever.
  static const int maxPages = 100;

  /// Fetches every page of accounts the user can access.
  ///
  /// Returns the same shape as [getAccounts], with all pages' accounts in
  /// `accounts` and the last page's `pagination`. If any page fails, that
  /// page's failure is returned and no accounts are, so a caller never
  /// replaces its cache with a partial list.
  Future<Map<String, dynamic>> getAllAccounts({
    required String accessToken,
    int perPage = maxPerPage,
  }) async {
    final accounts = <Account>[];
    Map<String, dynamic>? pagination;
    var page = 1;
    var totalPages = 1;

    while (page <= totalPages && page <= maxPages) {
      final result = await getAccounts(
        accessToken: accessToken,
        page: page,
        perPage: perPage,
      );
      if (result['success'] != true) return result;

      accounts.addAll((result['accounts'] as List<dynamic>).cast<Account>());
      pagination = result['pagination'] as Map<String, dynamic>?;
      totalPages = (pagination?['total_pages'] as num?)?.toInt() ?? 1;
      if (totalPages > maxPages) {
        return {
          'success': false,
          'error': 'Too many account pages to load ($totalPages)',
        };
      }
      page++;
    }

    return {
      'success': true,
      'accounts': accounts,
      'pagination': pagination,
    };
  }

  /// `POST /api/v1/accounts` (Sure+ `accounts.write`). [account] is the body
  /// inside the `account` key: `accountable_type`, `name`, `balance`, ... and
  /// the type's `accountable_attributes`. `'account'` holds the new
  /// [Account] on 201.
  Future<Map<String, dynamic>> createAccount({
    required String accessToken,
    required Map<String, dynamic> account,
  }) {
    return _write(
      'POST',
      Uri.parse('${ApiConfig.baseUrl}/api/v1/accounts'),
      accessToken,
      body: {'account': account},
      okStatus: 201,
      fallback: 'Failed to create account',
    );
  }

  /// `PATCH /api/v1/accounts/:id` (Sure+ `accounts.write`). Send only the
  /// fields that changed: linked accounts reject balance and currency (422).
  Future<Map<String, dynamic>> updateAccount({
    required String accessToken,
    required String id,
    required Map<String, dynamic> account,
  }) {
    return _write(
      'PATCH',
      _accountUri(id),
      accessToken,
      body: {'account': account},
      okStatus: 200,
      fallback: 'Failed to update account',
    );
  }

  /// `DELETE /api/v1/accounts/:id` (Sure+ `accounts.write`): 202, the
  /// server deletes it in the background. Linked accounts get 422.
  Future<Map<String, dynamic>> deleteAccount({
    required String accessToken,
    required String id,
  }) {
    return _write(
      'DELETE',
      _accountUri(id),
      accessToken,
      okStatus: 202,
      fallback: 'Failed to delete account',
    );
  }

  Uri _accountUri(String id) => Uri.parse(
      '${ApiConfig.baseUrl}/api/v1/accounts/${Uri.encodeComponent(id)}');

  /// `GET /api/v1/accounts/:id`. On Sure+ `accounts.loan_rates` servers the
  /// [Account] in `'account'` carries the type's `accountable` block.
  Future<Map<String, dynamic>> getAccount({
    required String accessToken,
    required String id,
  }) async {
    try {
      final response = await _client
          .get(_accountUri(id), headers: ApiConfig.getAuthHeaders(accessToken))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          return {'success': true, 'account': Account.fromJson(data)};
        }
      } else if (response.statusCode == 401) {
        return {'success': false, 'error': 'unauthorized'};
      }
      return {
        'success': false,
        'error': extractErrorMessage(response.body,
            fallback: 'Failed to load account'),
        'status': response.statusCode,
      };
    } catch (e) {
      LogService.instance.error(
          'AccountsService', 'GET account failed with ${e.runtimeType}');
      return {'success': false, 'error': 'Failed to load account'};
    }
  }

  /// Sends a write and maps the reply: success with `'account'` (when the
  /// body is an account), `'unauthorized'` on 401, otherwise the server's
  /// `message` as `'error'` and its `error` code (`insufficient_scope`,
  /// `forbidden`, `validation_failed`) as `'code'`.
  Future<Map<String, dynamic>> _write(
    String method,
    Uri url,
    String accessToken, {
    Map<String, dynamic>? body,
    required int okStatus,
    required String fallback,
  }) async {
    try {
      final request = http.Request(method, url)
        ..headers.addAll({
          ...ApiConfig.getAuthHeaders(accessToken),
          'Content-Type': 'application/json',
        });
      if (body != null) request.body = jsonEncode(body);
      final response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 30)),
      );

      if (response.statusCode == okStatus) {
        final data = response.body.isEmpty ? null : jsonDecode(response.body);
        return {
          'success': true,
          if (data is Map<String, dynamic> && data['account_type'] != null)
            'account': Account.fromJson(data),
          if (data is Map && data['message'] != null)
            'message': data['message'].toString(),
        };
      }
      if (response.statusCode == 401) {
        return {'success': false, 'error': 'unauthorized'};
      }
      String? code;
      try {
        final data = jsonDecode(response.body);
        if (data is Map && data['error'] is String) code = data['error'];
      } catch (_) {}
      return {
        'success': false,
        'error': extractErrorMessage(response.body, fallback: fallback),
        'status': response.statusCode,
        if (code != null) 'code': code,
      };
    } catch (e) {
      LogService.instance.error(
          'AccountsService', '$method account failed with ${e.runtimeType}');
      return {'success': false, 'error': fallback};
    }
  }

  Future<Map<String, dynamic>> getAccounts({
    required String accessToken,
    int page = 1,
    int perPage = 25,
  }) async {
    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/api/v1/accounts?page=$page&per_page=$perPage',
      );

      final response = await _client
          .get(
            url,
            headers: ApiConfig.getAuthHeaders(accessToken),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);

        final accountsList = (responseData['accounts'] as List)
            .map((json) => Account.fromJson(json))
            .toList();

        return {
          'success': true,
          'accounts': accountsList,
          'pagination': responseData['pagination'],
        };
      } else if (response.statusCode == 401) {
        return {
          'success': false,
          'error': 'unauthorized',
          'message': 'Session expired. Please login again.',
        };
      } else {
        final responseData = jsonDecode(response.body);
        return {
          'success': false,
          'error': responseData['error'] ?? 'Failed to fetch accounts',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error: ${e.toString()}',
      };
    }
  }
}
