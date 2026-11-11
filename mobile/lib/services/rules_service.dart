import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/rule.dart';
import 'api_config.dart';
import 'log_service.dart';
import 'response_list_parser.dart';

/// Read-only client for `/api/v1/rules` and `/api/v1/rule_runs`. Creating and
/// editing rules happens on the web.
///
/// Results are `{'success': bool, ...}` maps, with `'error': 'unauthorized'`
/// on 401.
class RulesService {
  static const Duration _timeout = Duration(seconds: 30);
  static const int _perPage = 100;
  static const int _maxPages = 20;

  final http.Client _client;
  final bool _ownsClient;

  RulesService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void close() {
    if (_ownsClient) _client.close();
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: query);

  /// Every rule, walking pages of 100, in the server's order (oldest first).
  /// `'rules'` holds a `List<Rule>`.
  Future<Map<String, dynamic>> listRules({required String accessToken}) async {
    const fallback = 'Failed to load rules';
    final rules = <Rule>[];
    try {
      var page = 1;
      var totalPages = 1;
      while (page <= totalPages && page <= _maxPages) {
        final response = await _client
            .get(_uri('/api/v1/rules', {'page': '$page', 'per_page': '$_perPage'}),
                headers: ApiConfig.getAuthHeaders(accessToken))
            .timeout(_timeout);
        if (response.statusCode != 200) return _failure(response, fallback);
        final data = jsonDecode(response.body);
        rules.addAll(
            extractJsonObjectList(data, key: 'data').map(Rule.fromJson));
        final meta = data is Map ? data['meta'] : null;
        totalPages = meta is Map && meta['total_pages'] is num
            ? (meta['total_pages'] as num).toInt()
            : 1;
        page++;
      }
      return {'success': true, 'rules': rules};
    } catch (e) {
      _log('listRules', e);
      return {'success': false, 'error': fallback};
    }
  }

  /// One rule with its conditions and actions. `'rule'` holds a [Rule];
  /// a deleted rule gives `'error': 'not_found'`.
  Future<Map<String, dynamic>> getRule({
    required String accessToken,
    required String id,
  }) async {
    const fallback = 'Failed to load rule';
    try {
      final response = await _client
          .get(_uri('/api/v1/rules/${Uri.encodeComponent(id)}'),
              headers: ApiConfig.getAuthHeaders(accessToken))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final json = data is Map ? data['data'] : null;
        if (json is! Map) return {'success': false, 'error': fallback};
        return {
          'success': true,
          'rule': Rule.fromJson(json.cast<String, dynamic>()),
        };
      }
      if (response.statusCode == 404) {
        return {'success': false, 'error': 'not_found'};
      }
      return _failure(response, fallback);
    } catch (e) {
      _log('getRule', e);
      return {'success': false, 'error': fallback};
    }
  }

  /// The newest [limit] runs of [ruleId] (`rule_id` filter, newest first).
  /// `'runs'` holds a `List<RuleRun>`.
  Future<Map<String, dynamic>> listRuleRuns({
    required String accessToken,
    required String ruleId,
    int limit = 10,
  }) async {
    const fallback = 'Failed to load rule runs';
    try {
      final response = await _client
          .get(
              _uri('/api/v1/rule_runs', {
                'rule_id': ruleId,
                'per_page': '$limit',
              }),
              headers: ApiConfig.getAuthHeaders(accessToken))
          .timeout(_timeout);
      if (response.statusCode != 200) return _failure(response, fallback);
      return {
        'success': true,
        'runs': extractJsonObjectList(jsonDecode(response.body), key: 'data')
            .map(RuleRun.fromJson)
            .toList(),
      };
    } catch (e) {
      _log('listRuleRuns', e);
      return {'success': false, 'error': fallback};
    }
  }

  Map<String, dynamic> _failure(http.Response response, String fallback) {
    if (response.statusCode == 401) {
      return {'success': false, 'error': 'unauthorized'};
    }
    return {
      'success': false,
      'error': extractErrorMessage(response.body, fallback: fallback),
    };
  }

  void _log(String operation, Object error) {
    LogService.instance
        .error('RulesService', '$operation failed with ${error.runtimeType}');
  }
}
