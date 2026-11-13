import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/provider_connection.dart';
import 'api_config.dart';
import 'log_service.dart';
import 'response_list_parser.dart';

/// Client for `GET /api/v1/provider_connections`, plus sync and disconnect
/// on Sure+ servers with `connections.manage`. Connecting and reconnecting
/// happen on the web.
class ProviderConnectionsService {
  /// Server error codes (403 and 422) that only the web Connections page can
  /// resolve. A failed result carries one of them as `'code'`.
  static const webFixCodes = {
    'forbidden',
    'insufficient_scope',
    'sync_not_supported',
    'disconnect_not_supported',
    'manual_sync_required',
    'not_connected',
    'reconnect_required',
    'unlink_failed',
  };

  static const Duration _timeout = Duration(seconds: 30);

  final http.Client _client;
  final bool _ownsClient;

  ProviderConnectionsService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void close() {
    if (_ownsClient) _client.close();
  }

  /// Every connection of the family. `'connections'` holds a
  /// `List<ProviderConnection>`.
  Future<Map<String, dynamic>> list({required String accessToken}) async {
    const fallback = 'Failed to load connections';
    try {
      final response = await _client
          .get(Uri.parse('${ApiConfig.baseUrl}/api/v1/provider_connections'),
              headers: ApiConfig.getAuthHeaders(accessToken))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'connections': extractJsonObjectList(data, key: 'data')
              .map(ProviderConnection.fromJson)
              .toList(),
        };
      }
      if (response.statusCode == 401) {
        return {'success': false, 'error': 'unauthorized'};
      }
      return {
        'success': false,
        'error': extractErrorMessage(response.body, fallback: fallback),
      };
    } catch (e) {
      LogService.instance.error(
          'ProviderConnectionsService', 'list failed with ${e.runtimeType}');
      return {'success': false, 'error': fallback};
    }
  }

  /// Queues a sync of [connection] (`POST .../:id/sync`). On 202,
  /// `'connection'` is the updated row (`syncing` true).
  Future<Map<String, dynamic>> sync({
    required String accessToken,
    required ProviderConnection connection,
  }) =>
      _manage(
        accessToken: accessToken,
        connection: connection,
        method: 'POST',
        path: '/sync',
        fallback: 'Failed to sync the connection',
      );

  /// Schedules [connection] for deletion (`DELETE .../:id`); its accounts
  /// stop syncing. On 202, `'connection'` is the row with
  /// `scheduledForDeletion` true.
  Future<Map<String, dynamic>> disconnect({
    required String accessToken,
    required ProviderConnection connection,
  }) =>
      _manage(
        accessToken: accessToken,
        connection: connection,
        method: 'DELETE',
        path: '',
        fallback: 'Failed to disconnect the connection',
      );

  /// Always sends `provider`: item ids live in per-provider tables and can
  /// collide (422 `ambiguous_connection` without it).
  Future<Map<String, dynamic>> _manage({
    required String accessToken,
    required ProviderConnection connection,
    required String method,
    required String path,
    required String fallback,
  }) async {
    final url = Uri.parse(
      '${ApiConfig.baseUrl}/api/v1/provider_connections/'
      '${Uri.encodeComponent(connection.id)}$path',
    ).replace(queryParameters: {'provider': connection.provider});
    try {
      final request = http.Request(method, url)
        ..headers.addAll(ApiConfig.getAuthHeaders(accessToken));
      final response = await http.Response.fromStream(
          await _client.send(request).timeout(_timeout));
      if (response.statusCode == 202 || response.statusCode == 200) {
        ProviderConnection? updated;
        try {
          final data = jsonDecode(response.body);
          if (data is Map<String, dynamic> && data['id'] != null) {
            updated = ProviderConnection.fromJson(data);
          }
        } catch (_) {
          // A 202 without a readable row still succeeded; the caller reloads.
        }
        return {'success': true, 'connection': updated};
      }
      if (response.statusCode == 401) {
        return {'success': false, 'error': 'unauthorized'};
      }
      String? code;
      try {
        final data = jsonDecode(response.body);
        if (data is Map && data['error'] is String) code = data['error'];
      } on FormatException {
        // Not JSON; no code.
      }
      return {
        'success': false,
        'status': response.statusCode,
        if (code != null) 'code': code,
        'error': extractErrorMessage(response.body, fallback: fallback),
      };
    } catch (e) {
      LogService.instance.error('ProviderConnectionsService',
          '$method connection failed with ${e.runtimeType}');
      return {'success': false, 'error': fallback};
    }
  }
}
