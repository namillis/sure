import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/provider_connection.dart';
import 'api_config.dart';
import 'log_service.dart';
import 'response_list_parser.dart';

/// Client for `GET /api/v1/provider_connections` (read-only; connecting,
/// reconnecting and removing happen on the web).
class ProviderConnectionsService {
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
      LogService.instance.error('ProviderConnectionsService',
          'list failed with ${e.runtimeType}');
      return {'success': false, 'error': fallback};
    }
  }
}
