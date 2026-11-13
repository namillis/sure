import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/goal.dart';
import 'api_config.dart';
import 'log_service.dart';
import 'response_list_parser.dart';

/// The body of `POST /api/v1/goals` and `PATCH /api/v1/goals/:id`, under
/// `goal`. Null fields are left out, so a PATCH keeps them; an empty
/// [targetDate] clears the date. Leaving out [accountIds] on PATCH keeps the
/// links. [allocations] maps an account id to its earmark ("300"), or to
/// null for the whole balance.
class GoalInput {
  const GoalInput({
    this.name,
    this.targetAmount,
    this.targetDate,
    this.color,
    this.icon,
    this.notes,
    this.kind,
    this.accountIds,
    this.allocations,
  });

  final String? name;
  final String? targetAmount;

  /// `yyyy-MM-dd`, or `''` for no date.
  final String? targetDate;
  final String? color;
  final String? icon;
  final String? notes;

  /// `one_off` or `maintained`.
  final String? kind;
  final List<String>? accountIds;
  final Map<String, String?>? allocations;

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (targetAmount != null) 'target_amount': targetAmount,
        if (targetDate != null) 'target_date': targetDate,
        if (color != null) 'color': color,
        if (icon != null) 'icon': icon,
        if (notes != null) 'notes': notes,
        if (kind != null) 'kind': kind,
        if (accountIds != null) 'account_ids': accountIds,
        if (allocations != null)
          'allocations': {
            for (final entry in allocations!.entries) entry.key: entry.value ?? '',
          },
      };
}

/// Sure+ goals and pledges (features `goals` and `goals.pledges`).
///
/// Results are `{'success': bool, ...}` maps, with `'error': 'unauthorized'`
/// on 401. Other failures carry the server's message in `'error'` and, when
/// the server names one, its error code in `'code'` (`feature_disabled` when
/// the user has no preview features, `insufficient_scope` for a read-only
/// sign-in).
class GoalsService {
  GoalsService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  static const _timeout = Duration(seconds: 30);

  void close() {
    if (_ownsClient) _client.close();
  }

  Map<String, String> _headers(String accessToken) => {
        ...ApiConfig.getAuthHeaders(accessToken),
        'Content-Type': 'application/json',
      };

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  static String _id(String id) => Uri.encodeComponent(id);

  /// `GET /api/v1/goals`, in the web's display order. `'goals'` holds a
  /// `List<Goal>`.
  Future<Map<String, dynamic>> listGoals({required String accessToken}) =>
      _send(
        'listGoals',
        'Failed to load goals',
        () => _client.get(_uri('/api/v1/goals'), headers: _headers(accessToken)),
        (body) => {
          'goals': [
            for (final json in extractJsonObjectList(body, key: 'goals'))
              if (json['id'] != null) Goal.fromJson(json),
          ],
        },
      );

  /// `GET /api/v1/goals/:id`. `'goal'` holds the [Goal].
  Future<Map<String, dynamic>> getGoal({
    required String accessToken,
    required String id,
  }) =>
      _send(
        'getGoal',
        'Failed to load goal',
        () => _client.get(_uri('/api/v1/goals/${_id(id)}'),
            headers: _headers(accessToken)),
        _goal,
      );

  /// `POST /api/v1/goals`. `'goal'` holds the new [Goal].
  Future<Map<String, dynamic>> createGoal({
    required String accessToken,
    required GoalInput goal,
  }) =>
      _send(
        'createGoal',
        'Failed to create goal',
        () => _client.post(_uri('/api/v1/goals'),
            headers: _headers(accessToken),
            body: jsonEncode({'goal': goal.toJson()})),
        _goal,
      );

  /// `PATCH /api/v1/goals/:id`. `'goal'` holds the updated [Goal].
  Future<Map<String, dynamic>> updateGoal({
    required String accessToken,
    required String id,
    required GoalInput goal,
  }) =>
      _send(
        'updateGoal',
        'Failed to save goal',
        () => _client.patch(_uri('/api/v1/goals/${_id(id)}'),
            headers: _headers(accessToken),
            body: jsonEncode({'goal': goal.toJson()})),
        _goal,
      );

  /// `DELETE /api/v1/goals/:id`.
  Future<Map<String, dynamic>> deleteGoal({
    required String accessToken,
    required String id,
  }) =>
      _send(
        'deleteGoal',
        'Failed to delete goal',
        () => _client.delete(_uri('/api/v1/goals/${_id(id)}'),
            headers: _headers(accessToken)),
        (_) => const {},
      );

  /// `POST /api/v1/goals/:id/pledges` ("I saved toward this") with an
  /// [amount] like "150" from one of the goal's linked accounts. `'goal'`
  /// holds the refreshed [Goal], `'pledge'` the new [GoalPledge].
  Future<Map<String, dynamic>> createPledge({
    required String accessToken,
    required String goalId,
    required String amount,
    required String accountId,
  }) =>
      _send(
        'createPledge',
        'Failed to record the pledge',
        () => _client.post(_uri('/api/v1/goals/${_id(goalId)}/pledges'),
            headers: _headers(accessToken),
            body: jsonEncode({
              'pledge': {'amount': amount, 'account_id': accountId},
            })),
        _pledge,
      );

  /// `PATCH /api/v1/goals/:id/pledges/:pledge_id/renew`: seven more days,
  /// the web's Extend.
  Future<Map<String, dynamic>> renewPledge({
    required String accessToken,
    required String goalId,
    required String pledgeId,
  }) =>
      _send(
        'renewPledge',
        'Failed to extend the pledge',
        () => _client.patch(
            _uri('/api/v1/goals/${_id(goalId)}/pledges/${_id(pledgeId)}/renew'),
            headers: _headers(accessToken)),
        _pledge,
      );

  /// `DELETE /api/v1/goals/:id/pledges/:pledge_id`: cancels the pledge.
  Future<Map<String, dynamic>> cancelPledge({
    required String accessToken,
    required String goalId,
    required String pledgeId,
  }) =>
      _send(
        'cancelPledge',
        'Failed to cancel the pledge',
        () => _client.delete(
            _uri('/api/v1/goals/${_id(goalId)}/pledges/${_id(pledgeId)}'),
            headers: _headers(accessToken)),
        _pledge,
      );

  /// `GET /api/v1/goals/summary` (feature `goals.summary`). `'summary'`
  /// holds the [GoalsSummary].
  Future<Map<String, dynamic>> getSummary({required String accessToken}) =>
      _send(
        'getSummary',
        'Failed to load the goals summary',
        () => _client.get(_uri('/api/v1/goals/summary'),
            headers: _headers(accessToken)),
        (body) =>
            {'summary': GoalsSummary.fromJson(body as Map<String, dynamic>)},
      );

  /// The lifecycle events `PATCH /api/v1/goals/:id/<action>` accepts.
  static const transitions = {
    'pause',
    'resume',
    'complete',
    'archive',
    'unarchive',
    'reopen',
  };

  /// `PATCH /api/v1/goals/:id/<action>` (feature `goals.lifecycle`), one of
  /// [transitions]. `'goal'` holds the updated [Goal]; a refused transition
  /// is 422 `invalid_transition` with the web's message in `'error'`.
  Future<Map<String, dynamic>> transitionGoal({
    required String accessToken,
    required String id,
    required String action,
  }) {
    assert(transitions.contains(action), 'unknown goal action $action');
    return _send(
      'transitionGoal',
      'Failed to update goal',
      () => _client.patch(
          _uri('/api/v1/goals/${_id(id)}/${Uri.encodeComponent(action)}'),
          headers: _headers(accessToken)),
      _goal,
    );
  }

  /// `POST /api/v1/goals/:id/consume` (feature `goals.lifecycle`): records
  /// [amount] (goal currency, like "200") as spent, from [accountId] when
  /// given. `'goal'` holds the updated [Goal]; a refusal is 422
  /// `consumption_refused` with a showable message in `'error'`.
  Future<Map<String, dynamic>> consumeGoal({
    required String accessToken,
    required String id,
    required String amount,
    String? accountId,
  }) =>
      _send(
        'consumeGoal',
        'Failed to record the spend',
        () => _client.post(_uri('/api/v1/goals/${_id(id)}/consume'),
            headers: _headers(accessToken),
            body: jsonEncode({
              'consumption': {
                'amount': amount,
                if (accountId != null) 'account_id': accountId,
              },
            })),
        _goal,
      );

  static Map<String, dynamic> _goal(dynamic body) =>
      {'goal': Goal.fromJson(body as Map<String, dynamic>)};

  static Map<String, dynamic> _pledge(dynamic body) {
    final map = body as Map<String, dynamic>;
    return {
      'goal': Goal.fromJson(map['goal'] as Map<String, dynamic>),
      'pledge': GoalPledge.fromJson(map['pledge'] as Map<String, dynamic>),
    };
  }

  Future<Map<String, dynamic>> _send(
    String operation,
    String fallback,
    Future<http.Response> Function() request,
    Map<String, dynamic> Function(dynamic body) parse,
  ) async {
    try {
      final response = await request().timeout(_timeout);
      final code = response.statusCode;
      if (code >= 200 && code < 300) {
        final body = response.body.trim().isEmpty
            ? null
            : jsonDecode(response.body);
        return {'success': true, ...parse(body)};
      }
      if (code == 401) return {'success': false, 'error': 'unauthorized'};
      return {'success': false, ..._failure(response.body, fallback)};
    } catch (e) {
      LogService.instance
          .error('GoalsService', '$operation failed with ${e.runtimeType}');
      return {'success': false, 'error': fallback};
    }
  }

  /// The server's error: the validation details when it lists them (they
  /// name the field), else its message; plus its error code.
  static Map<String, dynamic> _failure(String body, String fallback) {
    String? code;
    String? details;
    try {
      final data = jsonDecode(body);
      if (data is Map) {
        code = data['error']?.toString();
        final errors = data['errors'];
        if (errors is List && errors.isNotEmpty) {
          details = errors.map((e) => e.toString()).join('\n');
        }
      }
    } catch (_) {
      // Not JSON: fall back to the generic message.
    }
    return {
      'error': details ?? extractErrorMessage(body, fallback: fallback),
      if (code != null) 'code': code,
    };
  }
}
