import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/spending_vs_normal.dart';
import 'api_config.dart';
import 'log_service.dart';

/// Client for `GET /api/v1/spending_vs_normal`. A 403 or 404 comes back as
/// `'error': 'unavailable'` so the Home card can stay quiet.
class SpendingVsNormalService {
  static const Duration _timeout = Duration(seconds: 30);

  final http.Client _client;
  final bool _ownsClient;

  SpendingVsNormalService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void close() {
    if (_ownsClient) _client.close();
  }

  /// The comparison for [startDate]..[endDate], or the current month when
  /// both are null (the server needs both or neither). `'spending'` holds a
  /// [SpendingVsNormal].
  Future<Map<String, dynamic>> getSpendingVsNormal({
    required String accessToken,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    assert((startDate == null) == (endDate == null),
        'Pass both startDate and endDate, or neither');
    final format = DateFormat('yyyy-MM-dd');
    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/spending_vs_normal')
        .replace(
      queryParameters: startDate != null && endDate != null
          ? {
              'start_date': format.format(startDate),
              'end_date': format.format(endDate),
            }
          : null,
    );

    try {
      final response = await _client
          .get(url, headers: ApiConfig.getAuthHeaders(accessToken))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'spending': SpendingVsNormal.fromJson(
              jsonDecode(response.body) as Map<String, dynamic>),
        };
      }
      if (response.statusCode == 401) {
        return {'success': false, 'error': 'unauthorized'};
      }
      if (response.statusCode == 403 || response.statusCode == 404) {
        return {'success': false, 'error': 'unavailable'};
      }
      return {'success': false, 'error': 'Failed to load spending'};
    } catch (e) {
      LogService.instance.error(
        'SpendingVsNormalService',
        'getSpendingVsNormal failed with ${e.runtimeType}',
      );
      return {'success': false, 'error': 'Unable to load spending.'};
    }
  }
}
