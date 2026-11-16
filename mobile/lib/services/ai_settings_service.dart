import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ai_settings.dart';
import 'api_config.dart';
import 'api_error_result.dart';
import 'log_service.dart';

/// Settings → AI on a Sure+ server (`settings.ai`). Every call is
/// admin-only; a member gets 403. Results are `{'success': bool, ...}` maps:
/// `'error': 'unauthorized'` on 401, else a failure carries `'status'`, the
/// server's `'code'` (e.g. `forbidden`, `classifier_rule_missing`) and its
/// `'error'` message.
class AiSettingsService {
  AiSettingsService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  static const _timeout = Duration(seconds: 30);

  void close() {
    if (_ownsClient) _client.close();
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${ApiConfig.baseUrl}/api/v1/settings/ai$path')
          .replace(queryParameters: query);

  Map<String, String> _headers(String token) => {
        ...ApiConfig.getAuthHeaders(token),
        'Content-Type': 'application/json',
      };

  Map<String, dynamic>? _settings(int status, String body) =>
      status == 200 || status == 201
          ? {
              'settings': AiSettings.fromJson(
                  jsonDecode(body) as Map<String, dynamic>),
            }
          : null;

  /// `'settings'` holds the [AiSettings].
  Future<Map<String, dynamic>> get({required String accessToken}) => _send(
      'get',
      'Failed to load AI settings',
      () => _client.get(_uri(''), headers: _headers(accessToken)),
      _settings);

  /// `PATCH` with [aiSettings] as the `ai_settings` body (`prompts`,
  /// `classifier.settings`, `classifier.rules_active`). `'settings'` holds
  /// the saved [AiSettings].
  Future<Map<String, dynamic>> update({
    required String accessToken,
    required Map<String, dynamic> aiSettings,
  }) =>
      _send(
          'update',
          'Failed to save AI settings',
          () => _client.patch(_uri(''),
              headers: _headers(accessToken),
              body: jsonEncode({'ai_settings': aiSettings})),
          _settings);

  /// Queues a classifier run (202).
  Future<Map<String, dynamic>> runClassifier({required String accessToken}) =>
      _queue(accessToken, '/classifier/run');

  /// Queues clearing the classifier's locks (202).
  Future<Map<String, dynamic>> clearLocks({required String accessToken}) =>
      _queue(accessToken, '/classifier/clear_locks');

  Future<Map<String, dynamic>> _queue(String accessToken, String path) =>
      _send(
          'queue',
          'Failed to queue the job',
          () => _client.post(_uri(path), headers: _headers(accessToken)),
          (status, _) => status == 202 ? const {} : null);

  /// Adds the deleted Category classifier rule again (201), the fix for
  /// `classifier_rule_missing`. `'settings'` holds the updated settings.
  Future<Map<String, dynamic>> addClassifierRule({
    required String accessToken,
    String actionType = 'bayes_categorize',
  }) =>
      _send(
          'addRule',
          'Failed to add the classifier rule',
          () => _client.post(_uri('/classifier/rules'),
              headers: _headers(accessToken),
              body: jsonEncode({'action_type': actionType})),
          _settings);

  /// The last 30 days' LLM usage. `'usage'` holds the [AiUsage].
  Future<Map<String, dynamic>> usage({required String accessToken}) => _send(
        'usage',
        'Failed to load AI usage',
        () => _client.get(_uri('/usage'), headers: _headers(accessToken)),
        (status, body) => status == 200
            ? {
                'usage':
                    AiUsage.fromJson(jsonDecode(body) as Map<String, dynamic>),
              }
            : null,
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
      LogService.instance.error(
          'AiSettingsService', '$operation failed with ${e.runtimeType}');
      return {'success': false, 'error': fallback};
    }
  }
}
