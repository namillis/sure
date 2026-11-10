import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/insight.dart';
import 'api_config.dart';
import 'log_service.dart';

/// Client for `/api/v1/insights`. Insights are a preview feature: the server
/// answers 403 `feature_disabled` when the user has not enabled preview
/// features, which comes back as `'error': 'unavailable'` (as does 404, for
/// servers without the endpoint) so callers can stay quiet.
class InsightsService {
  static const Duration _timeout = Duration(seconds: 30);

  final http.Client _client;
  final bool _ownsClient;

  InsightsService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void close() {
    if (_ownsClient) _client.close();
  }

  /// Visible (not dismissed or expired) insights, highest priority first.
  /// `'insights'` holds a `List<Insight>`.
  Future<Map<String, dynamic>> getInsights({required String accessToken}) async {
    try {
      final response = await _client
          .get(Uri.parse('${ApiConfig.baseUrl}/api/v1/insights'),
              headers: ApiConfig.getAuthHeaders(accessToken))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          'success': true,
          'insights': (data['insights'] as List<dynamic>? ?? [])
              .map((j) => Insight.fromJson(j as Map<String, dynamic>))
              .toList(),
        };
      }
      return _failure(response.statusCode);
    } catch (e) {
      _log('getInsights', e);
      return {'success': false, 'error': 'Unable to load insights.'};
    }
  }

  /// Dismisses [id] (`PATCH /api/v1/insights/:id/acknowledge`, 204).
  Future<Map<String, dynamic>> acknowledge({
    required String accessToken,
    required String id,
  }) async {
    try {
      final response = await _client
          .patch(
              Uri.parse(
                  '${ApiConfig.baseUrl}/api/v1/insights/${Uri.encodeComponent(id)}/acknowledge'),
              headers: ApiConfig.getAuthHeaders(accessToken))
          .timeout(_timeout);
      if (response.statusCode == 204 || response.statusCode == 200) {
        return {'success': true};
      }
      return _failure(response.statusCode);
    } catch (e) {
      _log('acknowledge', e);
      return {'success': false, 'error': 'Unable to dismiss insight.'};
    }
  }

  Map<String, dynamic> _failure(int statusCode) {
    if (statusCode == 401) return {'success': false, 'error': 'unauthorized'};
    if (statusCode == 403 || statusCode == 404) {
      return {'success': false, 'error': 'unavailable'};
    }
    return {'success': false, 'error': 'Failed to load insights'};
  }

  void _log(String operation, Object error) {
    LogService.instance.error(
      'InsightsService',
      '$operation failed with ${error.runtimeType}',
    );
  }
}
