import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/budget.dart';
import 'api_config.dart';
import 'response_list_parser.dart';

/// Client for the budgets API (`/api/v1/budgets` and
/// `/api/v1/budget_categories`). Stock Sure is read-only; the PATCH calls
/// need a Sure+ server with `budgets.write`.
///
/// Results use the same `{'success': bool, ...}` map shape as the other
/// services so providers can treat them uniformly, with `'unauthorized'` as
/// the error for a 401.
class BudgetsService {
  BudgetsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 30);

  /// Lists budgets, optionally within a date window. The index endpoint does
  /// not include actual/available amounts; use [getBudget] for those.
  Future<Map<String, dynamic>> getBudgets({
    required String accessToken,
    DateTime? startDate,
    DateTime? endDate,
    int? page,
    int? perPage,
  }) async {
    final query = <String, String>{
      if (startDate != null) 'start_date': formatApiDate(startDate),
      if (endDate != null) 'end_date': formatApiDate(endDate),
      if (page != null) 'page': page.toString(),
      if (perPage != null) 'per_page': perPage.toString(),
    };

    final result = await _get(
      accessToken,
      '/api/v1/budgets',
      query,
      'Failed to load budgets',
    );
    if (result['success'] != true) return result;

    final budgets = extractJsonObjectList(result['data'], key: 'budgets')
        .map(Budget.fromJson)
        .where((b) => b.id.isNotEmpty)
        .toList();
    return {
      'success': true,
      'budgets': budgets,
      'pagination': _pagination(result['data']),
    };
  }

  /// Fetches one budget including its derived amounts.
  Future<Map<String, dynamic>> getBudget({
    required String accessToken,
    required String id,
  }) async {
    final result = await _get(
      accessToken,
      '/api/v1/budgets/${Uri.encodeComponent(id)}',
      const {},
      'Failed to load budget',
    );
    if (result['success'] != true) return result;

    final data = result['data'];
    if (data is! Map) {
      return {'success': false, 'error': 'Failed to load budget'};
    }
    return {
      'success': true,
      'budget': Budget.fromJson(data.cast<String, dynamic>()),
    };
  }

  /// Lists the category lines of a budget. Like the budgets index, this omits
  /// actual spending; use [getBudgetCategory] for those.
  Future<Map<String, dynamic>> getBudgetCategories({
    required String accessToken,
    String? budgetId,
    int? page,
    int? perPage,
  }) async {
    final query = <String, String>{
      if (budgetId != null) 'budget_id': budgetId,
      if (page != null) 'page': page.toString(),
      if (perPage != null) 'per_page': perPage.toString(),
    };

    final result = await _get(
      accessToken,
      '/api/v1/budget_categories',
      query,
      'Failed to load budget categories',
    );
    if (result['success'] != true) return result;

    final categories =
        extractJsonObjectList(result['data'], key: 'budget_categories')
            .map(BudgetCategory.fromJson)
            .where((c) => c.id.isNotEmpty)
            .toList();
    return {
      'success': true,
      'budget_categories': categories,
      'pagination': _pagination(result['data']),
    };
  }

  /// Fetches one budget category including actual spending and what is left.
  Future<Map<String, dynamic>> getBudgetCategory({
    required String accessToken,
    required String id,
  }) async {
    final result = await _get(
      accessToken,
      '/api/v1/budget_categories/${Uri.encodeComponent(id)}',
      const {},
      'Failed to load budget category',
    );
    if (result['success'] != true) return result;

    final data = result['data'];
    if (data is! Map) {
      return {'success': false, 'error': 'Failed to load budget category'};
    }
    return {
      'success': true,
      'budget_category': BudgetCategory.fromJson(data.cast<String, dynamic>()),
    };
  }

  /// `PATCH /api/v1/budgets/:id` (Sure+ `budgets.write`). Amounts are
  /// canonical decimal strings ("3500.50"); a null field is left unchanged.
  /// `'budget'` holds the updated [Budget]. See [_write] for the errors.
  Future<Map<String, dynamic>> updateBudget({
    required String accessToken,
    required String id,
    String? budgetedSpending,
    String? expectedIncome,
  }) async {
    final result = await _write(
      accessToken,
      '/api/v1/budgets/${Uri.encodeComponent(id)}',
      {
        'budget': {
          if (budgetedSpending != null) 'budgeted_spending': budgetedSpending,
          if (expectedIncome != null) 'expected_income': expectedIncome,
        },
      },
      'Failed to update budget',
    );
    if (result['success'] != true) return result;
    return {'success': true, 'budget': Budget.fromJson(result['data'])};
  }

  /// `PATCH /api/v1/budget_categories/:id` (Sure+ `budgets.write`). A null
  /// field is left unchanged. The server re-syncs a subcategory's parent and
  /// recomputes rollover, so reload the month afterwards.
  /// `'budget_category'` holds the updated [BudgetCategory].
  Future<Map<String, dynamic>> updateBudgetCategory({
    required String accessToken,
    required String id,
    String? budgetedSpending,
    bool? rolloverEnabled,
  }) async {
    final result = await _write(
      accessToken,
      '/api/v1/budget_categories/${Uri.encodeComponent(id)}',
      {
        'budget_category': {
          if (budgetedSpending != null) 'budgeted_spending': budgetedSpending,
          if (rolloverEnabled != null) 'rollover_enabled': rolloverEnabled,
        },
      },
      'Failed to update budget category',
    );
    if (result['success'] != true) return result;
    return {
      'success': true,
      'budget_category': BudgetCategory.fromJson(result['data']),
    };
  }

  /// PATCHes [body]. Failures carry the server's `message` as `'error'` and,
  /// where the screen reacts differently, a `'code'`: `insufficient_scope`
  /// (read-only sign-in), `forbidden` (budget shared read-only),
  /// `validation_failed` (422).
  Future<Map<String, dynamic>> _write(
    String accessToken,
    String path,
    Map<String, dynamic> body,
    String failureMessage,
  ) async {
    try {
      final response = await _client
          .patch(
            Uri.parse('${ApiConfig.baseUrl}$path'),
            headers: {
              ...ApiConfig.getAuthHeaders(accessToken),
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map) {
          return {'success': true, 'data': data.cast<String, dynamic>()};
        }
        return {'success': false, 'error': failureMessage};
      }
      if (response.statusCode == 401) {
        return {'success': false, 'error': 'unauthorized'};
      }
      return {
        'success': false,
        'error': extractErrorMessage(response.body, fallback: failureMessage),
        if (_errorCode(response) case final code?) 'code': code,
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  static String? _errorCode(http.Response response) {
    if (response.statusCode == 422) return 'validation_failed';
    if (response.statusCode != 403) return null;
    try {
      final data = jsonDecode(response.body);
      final error = data is Map ? data['error']?.toString() : null;
      if (error == 'insufficient_scope') return 'insufficient_scope';
    } on FormatException {
      // A non-JSON 403 is still a refusal of this budget.
    }
    return 'forbidden';
  }

  Future<Map<String, dynamic>> _get(
    String accessToken,
    String path,
    Map<String, String> query,
    String failureMessage,
  ) async {
    final baseUri = Uri.parse('${ApiConfig.baseUrl}$path');
    final url =
        query.isEmpty ? baseUri : baseUri.replace(queryParameters: query);

    try {
      final response = await _client.get(
        url,
        headers: {
          ...ApiConfig.getAuthHeaders(accessToken),
          'Content-Type': 'application/json',
        },
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else if (response.statusCode == 401) {
        return {'success': false, 'error': 'unauthorized'};
      } else if (response.statusCode == 404) {
        return {'success': false, 'error': 'not_found'};
      }
      return {
        'success': false,
        'error': extractErrorMessage(response.body, fallback: failureMessage),
      };
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  static Map<String, dynamic>? _pagination(dynamic data) {
    if (data is Map && data['pagination'] is Map) {
      return (data['pagination'] as Map).cast<String, dynamic>();
    }
    return null;
  }

  /// `YYYY-MM-DD`, the format the API date filters expect.
  static String formatApiDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
