import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/rule.dart';
import 'api_config.dart';
import 'log_service.dart';
import 'response_list_parser.dart';

/// The `rule` body of `POST`/`PATCH /api/v1/rules`: the read shape of
/// `GET /api/v1/rules/:id` with full `conditions` and `actions` lists.
/// [copyOf] carries the fields the editor doesn't show (effective date,
/// stop processing, group) onto a duplicate.
Map<String, dynamic> ruleWriteBody({
  required String? name,
  required bool active,
  required List<RuleCondition> conditions,
  required List<RuleAction> actions,
  Rule? copyOf,
}) =>
    {
      'name': (name?.trim().isEmpty ?? true) ? null : name!.trim(),
      'resource_type': copyOf?.resourceType ?? 'transaction',
      'active': active,
      if (copyOf != null) ...{
        'effective_date': copyOf.effectiveDate == null
            ? null
            : '${copyOf.effectiveDate!.year.toString().padLeft(4, '0')}-'
                '${copyOf.effectiveDate!.month.toString().padLeft(2, '0')}-'
                '${copyOf.effectiveDate!.day.toString().padLeft(2, '0')}',
        'stop_processing': copyOf.stopProcessing,
        if (copyOf.ruleGroupId != null) 'rule_group_id': copyOf.ruleGroupId,
      },
      'conditions': [for (final c in conditions) c.toJson()],
      'actions': [for (final a in actions) a.toJson()],
    };

/// Client for `/api/v1/rules` and `/api/v1/rule_runs`. Reads work on any
/// Sure server; create, update, delete and apply need a Sure+ server with
/// `rules.write`.
///
/// Results are `{'success': bool, ...}` maps, with `'error': 'unauthorized'`
/// on 401.
class RulesService {
  static const Duration _timeout = Duration(seconds: 30);

  /// Apply runs the rule inside the request.
  static const Duration _applyTimeout = Duration(seconds: 120);
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

  /// `POST /api/v1/rules` (Sure+ `rules.write`). [body] is the rule in the
  /// shape GET returns (see [ruleWriteBody]); ids in it are ignored, so
  /// posting a fetched rule makes a copy. `'rule'` holds the saved [Rule],
  /// `'warnings'` a `List<String>`.
  Future<Map<String, dynamic>> createRule({
    required String accessToken,
    required Map<String, dynamic> body,
  }) =>
      _save('createRule', accessToken,
          (headers) => _client.post(_uri('/api/v1/rules'),
              headers: headers, body: jsonEncode({'rule': body})),
          201);

  /// `PATCH /api/v1/rules/:id`. A `conditions` or `actions` list in [body]
  /// replaces the whole saved list; a list left out keeps it.
  Future<Map<String, dynamic>> updateRule({
    required String accessToken,
    required String id,
    required Map<String, dynamic> body,
  }) =>
      _save(
          'updateRule',
          accessToken,
          (headers) => _client.patch(
              _uri('/api/v1/rules/${Uri.encodeComponent(id)}'),
              headers: headers,
              body: jsonEncode({'rule': body})),
          200);

  /// `DELETE /api/v1/rules/:id` (204).
  Future<Map<String, dynamic>> deleteRule({
    required String accessToken,
    required String id,
  }) async {
    const fallback = 'Failed to delete rule';
    try {
      final response = await _client
          .delete(_uri('/api/v1/rules/${Uri.encodeComponent(id)}'),
              headers: ApiConfig.getAuthHeaders(accessToken))
          .timeout(_timeout);
      if (response.statusCode == 204 || response.statusCode == 200) {
        return {'success': true};
      }
      return _failure(response, fallback);
    } catch (e) {
      _log('deleteRule', e);
      return {'success': false, 'error': fallback};
    }
  }

  /// `POST /api/v1/rules/:id/apply`. Without [confirm] the server only
  /// answers 422 `confirmation_required`: then `'code'` is
  /// `confirmation_required` and `'confirmation'` a [RuleApplyConfirmation].
  /// With [confirm] it runs the rule inside the request (it can take a few
  /// seconds) and `'run'` holds the [RuleRun]; 409 gives `'code':
  /// 'rules_running'`.
  Future<Map<String, dynamic>> applyRule({
    required String accessToken,
    required String id,
    bool confirm = false,
  }) async {
    const fallback = 'Failed to apply rule';
    try {
      final response = await _client
          .post(
            _uri('/api/v1/rules/${Uri.encodeComponent(id)}/apply'),
            headers: _jsonHeaders(accessToken),
            body: jsonEncode(confirm ? {'confirm': true} : const {}),
          )
          .timeout(_applyTimeout);
      final data = _decode(response.body);
      if (response.statusCode == 201 || response.statusCode == 200) {
        final run = data is Map ? data['data'] : null;
        if (run is! Map) return {'success': false, 'error': fallback};
        return {
          'success': true,
          'run': RuleRun.fromJson(run.cast<String, dynamic>()),
        };
      }
      final failure = _failure(response, fallback);
      final confirmation = data is Map ? data['confirmation'] : null;
      if (failure['code'] == 'confirmation_required' && confirmation is Map) {
        failure['confirmation'] = RuleApplyConfirmation.fromJson(
            confirmation.cast<String, dynamic>());
      }
      return failure;
    } catch (e) {
      _log('applyRule', e);
      return {'success': false, 'error': fallback};
    }
  }

  Future<Map<String, dynamic>> _save(
    String operation,
    String accessToken,
    Future<http.Response> Function(Map<String, String> headers) send,
    int okStatus,
  ) async {
    const fallback = 'Failed to save rule';
    try {
      final response =
          await send(_jsonHeaders(accessToken)).timeout(_timeout);
      if (response.statusCode != okStatus && response.statusCode != 200) {
        return _failure(response, fallback);
      }
      final data = _decode(response.body);
      final json = data is Map ? data['data'] : null;
      if (json is! Map) return {'success': false, 'error': fallback};
      final warnings = data['warnings'];
      return {
        'success': true,
        'rule': Rule.fromJson(json.cast<String, dynamic>()),
        'warnings': warnings is List
            ? warnings.map((w) => w.toString()).toList()
            : const <String>[],
      };
    } catch (e) {
      _log(operation, e);
      return {'success': false, 'error': fallback};
    }
  }

  Map<String, String> _jsonHeaders(String accessToken) => {
        ...ApiConfig.getAuthHeaders(accessToken),
        'Content-Type': 'application/json',
      };

  static dynamic _decode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  /// `'error'` is the server's message; `'code'` its `error` value
  /// (`insufficient_scope`, `validation_failed`, `rules_running`, ...).
  Map<String, dynamic> _failure(http.Response response, String fallback) {
    if (response.statusCode == 401) {
      return {'success': false, 'error': 'unauthorized'};
    }
    final data = _decode(response.body);
    final code = data is Map ? data['error']?.toString() : null;
    return {
      'success': false,
      'error': extractErrorMessage(response.body, fallback: fallback),
      if (code != null && code.isNotEmpty) 'code': code,
      'status': response.statusCode,
    };
  }

  void _log(String operation, Object error) {
    LogService.instance
        .error('RulesService', '$operation failed with ${error.runtimeType}');
  }
}
