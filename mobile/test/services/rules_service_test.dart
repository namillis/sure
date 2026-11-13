import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/rule.dart';
import 'package:sure_mobile/services/rules_service.dart';

Map<String, dynamic> ruleJson(String id, {String? name, bool active = true}) =>
    {
      'id': id,
      'name': name,
      'resource_type': 'transaction',
      'active': active,
      'effective_date': null,
      'position': 0,
      'stop_processing': false,
      'conditions': [
        {
          'id': 'cond1',
          'condition_type': 'transaction_name',
          'operator': 'like',
          'value': 'Coffee',
          'sub_conditions': [],
        },
        {
          'id': 'cond2',
          'condition_type': 'compound',
          'operator': 'or',
          'value': null,
          'sub_conditions': [
            {
              'id': 'cond3',
              'condition_type': 'transaction_amount',
              'operator': '>',
              'value': '10',
              'sub_conditions': [],
            },
          ],
        },
      ],
      'actions': [
        {'id': 'a1', 'action_type': 'set_transaction_category', 'value': 'cat1'},
      ],
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    };

Map<String, dynamic> meta(int page, int totalPages) => {
      'current_page': page,
      'next_page': page < totalPages ? page + 1 : null,
      'prev_page': page > 1 ? page - 1 : null,
      'total_pages': totalPages,
      'total_count': totalPages,
      'per_page': 100,
    };

void main() {
  group('RulesService', () {
    test('listRules walks every page', () async {
      final pages = <String?>[];
      final service = RulesService(
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/rules');
          expect(request.url.queryParameters['per_page'], '100');
          final page = request.url.queryParameters['page'];
          pages.add(page);
          return http.Response(
              jsonEncode({
                'data': [ruleJson('r$page', name: 'Rule $page')],
                'meta': meta(int.parse(page!), 2),
              }),
              200);
        }),
      );

      final result = await service.listRules(accessToken: 't');

      expect(pages, ['1', '2']);
      final rules = (result['rules'] as List).cast<Rule>();
      expect(rules.map((r) => r.id), ['r1', 'r2']);
      expect(rules.first.conditions, hasLength(2));
      expect(rules.first.conditions.last.isCompound, true);
      expect(rules.first.conditions.last.subConditions.single.value, '10');
      expect(rules.first.actions.single.actionType, 'set_transaction_category');
    });

    test('listRules returns unauthorized on 401', () async {
      final service = RulesService(
          client: MockClient((_) async => http.Response('{}', 401)));
      expect((await service.listRules(accessToken: 't'))['error'],
          'unauthorized');
    });

    test('getRule parses data and maps 404 to not_found', () async {
      final service = RulesService(
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/rules/r1') {
            return http.Response(
                jsonEncode({'data': ruleJson('r1', active: false)}), 200);
          }
          return http.Response('{"error":"not_found"}', 404);
        }),
      );

      final ok = await service.getRule(accessToken: 't', id: 'r1');
      expect((ok['rule'] as Rule).active, false);
      expect((ok['rule'] as Rule).hasName, false);
      expect((await service.getRule(accessToken: 't', id: 'gone'))['error'],
          'not_found');
    });

    test('listRuleRuns filters by rule and limits the page', () async {
      final service = RulesService(
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/rule_runs');
          expect(request.url.queryParameters,
              {'rule_id': 'r1', 'per_page': '5'});
          return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': 'run1',
                    'rule_id': 'r1',
                    'rule_name': null,
                    'execution_type': 'manual',
                    'status': 'success',
                    'transactions_queued': 12,
                    'transactions_processed': 12,
                    'transactions_modified': 4,
                    'pending_jobs_count': 0,
                    'executed_at': '2026-11-10T09:30:00Z',
                    'error_message': null,
                    'rule': null,
                  },
                ],
                'meta': meta(1, 1),
              }),
              200);
        }),
      );

      final result =
          await service.listRuleRuns(accessToken: 't', ruleId: 'r1', limit: 5);
      final run = (result['runs'] as List).cast<RuleRun>().single;
      expect(run.status, 'success');
      expect(run.transactionsModified, 4);
      expect(run.executedAt, DateTime.utc(2026, 11, 10, 9, 30));
    });

    test('listRuleRuns passes on validation errors', () async {
      final service = RulesService(
          client: MockClient((_) async => http.Response(
              '{"error":"validation_failed","message":"rule_id must be a valid UUID"}',
              422)));
      expect(
          (await service.listRuleRuns(accessToken: 't', ruleId: 'x'))['error'],
          'rule_id must be a valid UUID');
    });
  });

  group('RulesService writes (rules.write)', () {
    test('ruleWriteBody sends full lists with compound sub_conditions', () {
      final rule = Rule.fromJson(ruleJson('r1'));
      final body = ruleWriteBody(
        name: '  ',
        active: true,
        conditions: rule.conditions,
        actions: rule.actions,
      );
      expect(body['name'], isNull);
      expect(body['resource_type'], 'transaction');
      expect(body.containsKey('stop_processing'), isFalse);
      expect(body['conditions'], [
        {
          'id': 'cond1',
          'condition_type': 'transaction_name',
          'operator': 'like',
          'value': 'Coffee',
        },
        {
          'id': 'cond2',
          'condition_type': 'compound',
          'operator': 'or',
          'value': null,
          'sub_conditions': [
            {
              'id': 'cond3',
              'condition_type': 'transaction_amount',
              'operator': '>',
              'value': '10',
            },
          ],
        },
      ]);
      expect(body['actions'], [
        {'id': 'a1', 'action_type': 'set_transaction_category', 'value': 'cat1'},
      ]);
    });

    test('ruleWriteBody copies hidden fields for a duplicate', () {
      final source = Rule.fromJson({
        ...ruleJson('r1'),
        'effective_date': '2026-03-01',
        'stop_processing': true,
        'rule_group_id': 'g1',
      });
      final body = ruleWriteBody(
        name: 'Copy',
        active: false,
        conditions: const [],
        actions: source.actions,
        copyOf: source,
      );
      expect(body['effective_date'], '2026-03-01');
      expect(body['stop_processing'], true);
      expect(body['rule_group_id'], 'g1');
      expect(body['active'], false);
    });

    test('createRule posts the wrapped body and returns rule and warnings',
        () async {
      late http.Request sent;
      final service = RulesService(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
              jsonEncode({
                'data': ruleJson('new', name: 'Coffee'),
                'warnings': ['Switched off'],
              }),
              201);
        }),
      );
      final result = await service.createRule(
          accessToken: 't', body: {'name': 'Coffee', 'actions': []});
      expect(sent.method, 'POST');
      expect(sent.url.path, '/api/v1/rules');
      expect(sent.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(sent.body), {
        'rule': {'name': 'Coffee', 'actions': []},
      });
      expect(result['success'], true);
      expect((result['rule'] as Rule).id, 'new');
      expect(result['warnings'], ['Switched off']);
    });

    test('updateRule patches and surfaces 422 and insufficient_scope',
        () async {
      var status = 422;
      final service = RulesService(
        client: MockClient((request) async {
          expect(request.method, 'PATCH');
          expect(request.url.path, '/api/v1/rules/r1');
          return status == 422
              ? http.Response(
                  jsonEncode({
                    'error': 'validation_failed',
                    'message': 'Rule must have at least one action',
                    'errors': ['Rule must have at least one action'],
                  }),
                  422)
              : http.Response(
                  jsonEncode({
                    'error': 'insufficient_scope',
                    'message': 'This action requires the read_write scope',
                  }),
                  403);
        }),
      );
      final invalid =
          await service.updateRule(accessToken: 't', id: 'r1', body: {});
      expect(invalid['success'], false);
      expect(invalid['error'], 'Rule must have at least one action');
      expect(invalid['code'], 'validation_failed');

      status = 403;
      final scope =
          await service.updateRule(accessToken: 't', id: 'r1', body: {});
      expect(scope['code'], 'insufficient_scope');
    });

    test('deleteRule accepts 204', () async {
      final service = RulesService(
        client: MockClient((request) async {
          expect(request.method, 'DELETE');
          expect(request.url.path, '/api/v1/rules/r1');
          return http.Response('', 204);
        }),
      );
      expect((await service.deleteRule(accessToken: 't', id: 'r1'))['success'],
          true);
    });

    test('applyRule: confirmation, run, and 409', () async {
      final bodies = <dynamic>[];
      var running = false;
      final service = RulesService(
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/rules/r1/apply');
          final body = jsonDecode(request.body);
          bodies.add(body);
          if (running) {
            return http.Response(
                jsonEncode({
                  'error': 'rules_running',
                  'message': 'Rules are already running for this family.',
                }),
                409);
          }
          if (body is Map && body['confirm'] == true) {
            return http.Response(
                jsonEncode({
                  'data': {
                    'id': 'run1',
                    'rule_id': 'r1',
                    'execution_type': 'manual',
                    'status': 'success',
                    'transactions_queued': 0,
                    'transactions_processed': 12,
                    'transactions_modified': 4,
                    'pending_jobs_count': 1,
                    'executed_at': '2026-11-10T09:30:00Z',
                  },
                }),
                201);
          }
          return http.Response(
              jsonEncode({
                'error': 'confirmation_required',
                'message': 'Send confirm: true to apply it.',
                'confirmation': {
                  'affected_resource_count': 12,
                  'resource_type': 'transaction',
                  'active_rules_above_count': 2,
                  'auto_categorize': true,
                  'ai_model': 'gpt-4.1-mini',
                  'estimated_ai_cost': 0.0123,
                },
              }),
              422);
        }),
      );

      final first = await service.applyRule(accessToken: 't', id: 'r1');
      expect(first['code'], 'confirmation_required');
      final confirmation = first['confirmation'] as RuleApplyConfirmation;
      expect(confirmation.affectedCount, 12);
      expect(confirmation.activeRulesAboveCount, 2);
      expect(confirmation.autoCategorize, true);
      expect(confirmation.aiModel, 'gpt-4.1-mini');
      expect(confirmation.estimatedAiCost, 0.0123);

      final applied =
          await service.applyRule(accessToken: 't', id: 'r1', confirm: true);
      final run = applied['run'] as RuleRun;
      expect(run.transactionsModified, 4);
      expect(run.pendingJobsCount, 1);
      expect(bodies, [{}, {'confirm': true}]);

      running = true;
      final busy =
          await service.applyRule(accessToken: 't', id: 'r1', confirm: true);
      expect(busy['success'], false);
      expect(busy['code'], 'rules_running');
    });
  });
}
