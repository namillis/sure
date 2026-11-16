import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/household.dart';
import 'api_config.dart';
import 'log_service.dart';
import 'response_list_parser.dart';

/// Household members, invitations, account sharing and budget sharing on
/// Sure+ servers (`household.members`, `accounts.sharing`,
/// `budgets.sharing`). Accepting an invitation stays on the web.
///
/// Every call returns `{'success': bool, ...}`; `'error'` is `'unauthorized'`
/// on 401, else the server's `message`. A failed result also carries
/// `'status'` and, when the server sent one, the error `'code'`.
class HouseholdService {
  HouseholdService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  static const Duration _timeout = Duration(seconds: 30);

  final http.Client _client;
  final bool _ownsClient;

  void close() {
    if (_ownsClient) _client.close();
  }

  /// `'household'` holds a [Household].
  Future<Map<String, dynamic>> members({required String accessToken}) =>
      _send(accessToken, 'GET', '/family/members',
          fallback: 'Failed to load the household',
          parse: (data) => {'household': Household.fromJson(data)});

  /// [role] is `admin`, `member` or `guest`. `'delivery'` is `email` or
  /// `link_only`.
  Future<Map<String, dynamic>> invite({
    required String accessToken,
    required String email,
    required String role,
  }) =>
      _send(accessToken, 'POST', '/invitations',
          body: {
            'invitation': {'email': email, 'role': role},
          },
          fallback: 'Failed to send the invitation',
          parse: (data) => {'delivery': data['delivery']?.toString()});

  Future<Map<String, dynamic>> revokeInvitation({
    required String accessToken,
    required String id,
  }) =>
      _send(accessToken, 'DELETE', '/invitations/${Uri.encodeComponent(id)}',
          fallback: 'Failed to revoke the invitation');

  /// `'sharing'` holds an [AccountSharing].
  Future<Map<String, dynamic>> accountSharing({
    required String accessToken,
    required String accountId,
  }) =>
      _send(accessToken, 'GET', _accountPath(accountId),
          fallback: 'Failed to load sharing',
          parse: (data) => {'sharing': AccountSharing.fromJson(data)});

  /// Owner only: sets one member's [permission] (`none` unshares).
  Future<Map<String, dynamic>> setAccountMember({
    required String accessToken,
    required String accountId,
    required String userId,
    required String permission,
  }) =>
      _send(accessToken, 'PATCH', _accountPath(accountId),
          body: {
            'sharing': {
              'members': [
                {'user_id': userId, 'permission': permission},
              ],
            },
          },
          fallback: 'Failed to update sharing',
          parse: (data) => {'sharing': AccountSharing.fromJson(data)});

  /// For someone the account is shared with: their own finance inclusion.
  Future<Map<String, dynamic>> setIncludeInFinances({
    required String accessToken,
    required String accountId,
    required bool include,
  }) =>
      _send(accessToken, 'PATCH', _accountPath(accountId),
          body: {
            'sharing': {'include_in_finances': include},
          },
          fallback: 'Failed to update sharing',
          parse: (data) => {'sharing': AccountSharing.fromJson(data)});

  /// `'sharing'` holds a [BudgetSharing].
  Future<Map<String, dynamic>> budgetSharing({required String accessToken}) =>
      _send(accessToken, 'GET', '/budget_shares',
          fallback: 'Failed to load budget sharing',
          parse: (data) => {'sharing': BudgetSharing.fromJson(data)});

  /// [permission] is `none`, `read_only` or `read_write`.
  Future<Map<String, dynamic>> setBudgetMember({
    required String accessToken,
    required String userId,
    required String permission,
  }) =>
      _send(accessToken, 'PATCH', '/budget_shares',
          body: {
            'budget_shares': {
              'members': [
                {'user_id': userId, 'permission': permission},
              ],
            },
          },
          fallback: 'Failed to update budget sharing',
          parse: (data) => {'sharing': BudgetSharing.fromJson(data)});

  static String _accountPath(String accountId) =>
      '/accounts/${Uri.encodeComponent(accountId)}/sharing';

  Future<Map<String, dynamic>> _send(
    String accessToken,
    String method,
    String path, {
    Map<String, dynamic>? body,
    required String fallback,
    Map<String, dynamic> Function(Map<String, dynamic> data)? parse,
  }) async {
    try {
      final request =
          http.Request(method, Uri.parse('${ApiConfig.baseUrl}/api/v1$path'))
            ..headers.addAll(ApiConfig.getAuthHeaders(accessToken));
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final response = await http.Response.fromStream(
          await _client.send(request).timeout(_timeout));
      final status = response.statusCode;
      if (status >= 200 && status < 300) {
        if (parse == null || response.body.isEmpty) return {'success': true};
        final data = jsonDecode(response.body);
        return {
          'success': true,
          ...parse(data is Map<String, dynamic> ? data : const {}),
        };
      }
      if (status == 401) return {'success': false, 'error': 'unauthorized'};
      String? code;
      try {
        final data = jsonDecode(response.body);
        if (data is Map && data['error'] is String) code = data['error'];
      } on FormatException {
        // Not JSON; no code.
      }
      return {
        'success': false,
        'status': status,
        if (code != null) 'code': code,
        'error': extractErrorMessage(response.body, fallback: fallback),
      };
    } catch (e) {
      LogService.instance
          .error('HouseholdService', '$method $path failed: ${e.runtimeType}');
      return {'success': false, 'error': fallback};
    }
  }
}
