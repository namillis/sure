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
}
