import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/api_key.dart';
import 'api_config.dart';
import 'api_error_result.dart';
import 'log_service.dart';
import 'response_list_parser.dart';

/// The signed-in user's API keys (Sure+ `settings.api_keys`). Results are
/// `{'success': bool, ...}` maps: `'error': 'unauthorized'` on 401, else a
/// failure carries `'status'`, the server's `'code'` (e.g.
/// `rate_limit_exceeded`, `insufficient_scope`) and its `'error'` message.
///
/// The `plain_key` a create returns is handed to the caller once and never
/// logged or stored here.
class ApiKeysService {
  ApiKeysService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  static const _timeout = Duration(seconds: 30);

  void close() {
    if (_ownsClient) _client.close();
  }

  Uri _uri([String? id]) => Uri.parse('${ApiConfig.baseUrl}/api/v1/api_keys'
      '${id == null ? '' : '/${Uri.encodeComponent(id)}'}');

  Map<String, String> _headers(String token) => {
        ...ApiConfig.getAuthHeaders(token),
        'Content-Type': 'application/json',
      };

  /// `'keys'` holds a `List<ApiKey>`, newest first.
  Future<Map<String, dynamic>> list({required String accessToken}) => _send(
        'list',
        'Failed to load API keys',
        () => _client.get(_uri(), headers: _headers(accessToken)),
        (status, body) => status == 200
            ? {
                'keys': extractJsonObjectList(jsonDecode(body), key: 'data')
                    .map(ApiKey.fromJson)
                    .toList(),
              }
            : null,
      );

  /// Creates a key with [scope] `read` or `read_write`. On 201, `'key'` is
  /// the [ApiKey] and `'plainKey'` the full key, shown once.
  Future<Map<String, dynamic>> create({
    required String accessToken,
    required String name,
    required String scope,
  }) =>
      _send(
        'create',
        'Failed to create the API key',
        () => _client.post(_uri(),
            headers: _headers(accessToken),
            body: jsonEncode({
              'api_key': {
                'name': name,
                'scopes': [scope],
              },
            })),
        (status, body) {
          if (status != 201) return null;
          final data = (jsonDecode(body) as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
          return {
            'key': ApiKey.fromJson(data),
            'plainKey': data['plain_key']?.toString() ?? '',
          };
        },
      );

  /// Revokes the key [id] (204).
  Future<Map<String, dynamic>> revoke({
    required String accessToken,
    required String id,
  }) =>
      _send(
        'revoke',
        'Failed to revoke the API key',
        () => _client.delete(_uri(id), headers: _headers(accessToken)),
        (status, _) => status == 204 || status == 200 ? const {} : null,
      );

  Future<Map<String, dynamic>> _send(
    String operation,
    String fallback,
    Future<http.Response> Function() request,
    Map<String, dynamic>? Function(int status, String body) parse,
  ) async {
    try {
      final response = await request().timeout(_timeout);
      final parsed = parse(response.statusCode, response.body);
      if (parsed != null) return {'success': true, ...parsed};
      if (response.statusCode == 401) {
        return {'success': false, 'error': 'unauthorized'};
      }
      return errorResult(response, fallback: fallback);
    } catch (e) {
      LogService.instance
          .error('ApiKeysService', '$operation failed with ${e.runtimeType}');
      return {'success': false, 'error': fallback};
    }
  }
}
