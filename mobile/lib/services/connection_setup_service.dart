import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/connection_setup.dart';
import '../models/provider_connection.dart';
import 'api_config.dart';
import 'api_error_result.dart';
import 'log_service.dart';
import 'response_list_parser.dart';

/// Sure+ round 4a: adding connections from the app.
///
/// - `GET /api/v1/provider_connections/available` (`connections.available`);
/// - `POST /api/v1/web_handoffs` (`connections.web_handoff`);
/// - `POST /api/v1/provider_connections`, `GET .../:id/pending_accounts` and
///   `POST .../:id/complete_setup` (`connections.token_create`).
///
/// Failures are `{'success': false, 'status', 'code', 'error'}` maps, with
/// `'error': 'unauthorized'` on 401. Handoff URLs and provider secrets are
/// never logged: the catch blocks log only the exception type.
class ConnectionSetupService {
  static const Duration _timeout = Duration(seconds: 30);

  final http.Client _client;
  final bool _ownsClient;

  ConnectionSetupService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void close() {
    if (_ownsClient) _client.close();
  }

  /// The "Add connection" list. `'connections'` holds a
  /// `List<AvailableConnection>`; guests get an empty list.
  Future<Map<String, dynamic>> available({required String accessToken}) =>
      _send(
        'GET',
        '/api/v1/provider_connections/available',
        accessToken: accessToken,
        fallback: 'Failed to load connections',
        onSuccess: (data) => {
          'connections': extractJsonObjectList(data, key: 'data')
              .map(AvailableConnection.fromJson)
              .toList(),
        },
      );

  /// A one-time URL that opens [path] signed in. `'url'` holds the [Uri].
  /// The URL carries a single-use token: callers must not log, cache or show
  /// it.
  Future<Map<String, dynamic>> createHandoff({
    required String accessToken,
    required String path,
  }) =>
      _send(
        'POST',
        '/api/v1/web_handoffs',
        accessToken: accessToken,
        body: {
          'web_handoff': {'path': path},
        },
        fallback: 'Failed to open the page',
        onSuccess: (data) {
          final url = data is Map ? Uri.tryParse('${data['url'] ?? ''}') : null;
          if (url == null || !url.hasScheme) throw const FormatException();
          return {'url': url};
        },
      );

  /// Creates a token connection. [fields] are the provider's `connection`
  /// attributes, secrets included. On 201: `'connection'` (the row),
  /// `'setupRequired'` and `'awaitingAccounts'`.
  Future<Map<String, dynamic>> create({
    required String accessToken,
    required String provider,
    required Map<String, String> fields,
  }) =>
      _send(
        'POST',
        '/api/v1/provider_connections',
        accessToken: accessToken,
        body: {'provider': provider, 'connection': fields},
        fallback: 'Failed to connect',
        onSuccess: (data) {
          final row = (data as Map).cast<String, dynamic>();
          return {
            'connection': ProviderConnection.fromJson(row),
            'setupRequired': row['setup_required'] == true,
            'awaitingAccounts': row['awaiting_accounts'] == true,
          };
        },
      );

  /// `'accounts'` holds a `List<PendingAccount>`; `'awaitingAccounts'` is
  /// true until the provider's first sync has listed them.
  Future<Map<String, dynamic>> pendingAccounts({
    required String accessToken,
    required String connectionId,
    required String provider,
  }) =>
      _send(
        'GET',
        '/api/v1/provider_connections/'
            '${Uri.encodeComponent(connectionId)}/pending_accounts',
        query: {'provider': provider},
        accessToken: accessToken,
        fallback: 'Failed to load the accounts',
        onSuccess: (data) => {
          'accounts': extractJsonObjectList(data, key: 'data')
              .map(PendingAccount.fromJson)
              .toList(),
          'awaitingAccounts':
              data is Map && data['awaiting_accounts'] == true,
        },
      );

  /// Imports or skips [accounts] (`{id, import, accountable_type, subtype}`
  /// maps). [syncStartDate] only applies to SimpleFIN and Binance.
  /// `'createdAccountIds'` lists the new accounts.
  Future<Map<String, dynamic>> completeSetup({
    required String accessToken,
    required String connectionId,
    required String provider,
    required List<Map<String, dynamic>> accounts,
    DateTime? syncStartDate,
  }) =>
      _send(
        'POST',
        '/api/v1/provider_connections/'
            '${Uri.encodeComponent(connectionId)}/complete_setup',
        query: {'provider': provider},
        accessToken: accessToken,
        body: {
          if (syncStartDate != null)
            'sync_start_date': _isoDay(syncStartDate),
          'accounts': accounts,
        },
        fallback: 'Failed to import the accounts',
        onSuccess: (data) => {
          'createdAccountIds': [
            for (final id in (data is Map
                ? data['created_account_ids'] as List<dynamic>? ?? const []
                : const []))
              id.toString(),
          ],
        },
      );

  static String _isoDay(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    required String accessToken,
    required String fallback,
    required Map<String, dynamic> Function(dynamic data) onSuccess,
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    var url = Uri.parse('${ApiConfig.baseUrl}$path');
    if (query != null) url = url.replace(queryParameters: query);
    try {
      final request = http.Request(method, url)
        ..headers.addAll(ApiConfig.getAuthHeaders(accessToken));
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final response = await http.Response.fromStream(
          await _client.send(request).timeout(_timeout));
      final code = response.statusCode;
      if (code == 200 || code == 201) {
        return {'success': true, ...onSuccess(jsonDecode(response.body))};
      }
      if (code == 401) return {'success': false, 'error': 'unauthorized'};
      return errorResult(response, fallback: fallback);
    } catch (e) {
      // Only the type: the request may hold secrets, the response a URL.
      LogService.instance.error(
          'ConnectionSetupService', '$method $path failed with ${e.runtimeType}');
      return {'success': false, 'error': fallback};
    }
  }
}
