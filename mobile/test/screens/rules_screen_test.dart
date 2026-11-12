import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/screens/rule_detail_screen.dart';
import 'package:sure_mobile/screens/rules_screen.dart';
import 'package:sure_mobile/services/rules_service.dart';
import 'package:sure_mobile/utils/rule_text.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';

import '../support/l10n_harness.dart';

Map<String, dynamic> _rule(String id, {String? name, bool active = true}) => {
      'id': id,
      'name': name,
      'resource_type': 'transaction',
      'active': active,
      'effective_date': '2026-03-01',
      'conditions': [
        {
          'condition_type': 'transaction_name',
          'operator': 'like',
          'value': 'Coffee',
          'sub_conditions': [],
        },
        {
          'condition_type': 'compound',
          'operator': 'or',
          'value': null,
          'sub_conditions': [
            {
              'condition_type': 'transaction_amount',
              'operator': '>',
              'value': '10',
              'sub_conditions': [],
            },
            {
              'condition_type': 'transaction_category',
              'operator': '=',
              'value': 'cat1',
              'sub_conditions': [],
            },
          ],
        },
      ],
      'actions': [
        {'action_type': 'set_transaction_category', 'value': 'cat1'},
        {'action_type': 'exclude_transaction', 'value': null},
      ],
    };

const _meta = {'current_page': 1, 'total_pages': 1, 'per_page': 100};

Map<String, dynamic> _run(String status,
        {int processed = 10, int modified = 3, String? error}) =>
    {
      'id': 'run-$status',
      'rule_id': 'r1',
      'execution_type': 'manual',
      'status': status,
      'transactions_queued': 7,
      'transactions_processed': processed,
      'transactions_modified': modified,
      'executed_at': '2026-11-10T09:30:00Z',
      'error_message': error,
    };

String? _names(RuleValueKind kind, String id) =>
    kind == RuleValueKind.category && id == 'cat1' ? 'Food' : null;

void main() {
  MockClient server({
    List<Map<String, dynamic>>? rules,
    List<Map<String, dynamic>>? runs,
    int ruleStatus = 200,
  }) =>
      MockClient((request) async {
        final path = request.url.path;
        if (path == '/api/v1/rules') {
          return http.Response(
              jsonEncode({'data': rules ?? [], 'meta': _meta}), 200);
        }
        if (path.startsWith('/api/v1/rules/')) {
          if (ruleStatus != 200) return http.Response('{}', ruleStatus);
          final id = path.split('/').last;
          return http.Response(
              jsonEncode({'data': _rule(id, name: 'Coffee runs')}), 200);
        }
        if (path == '/api/v1/rule_runs') {
          expect(request.url.queryParameters['rule_id'], isNotEmpty);
          return http.Response(
              jsonEncode({'data': runs ?? [], 'meta': _meta}), 200);
        }
        return http.Response('{}', 404);
      });

  Future<void> pumpList(WidgetTester tester, MockClient client) =>
      pumpLocalized(
        tester,
        RulesScreen(
          service: RulesService(client: client),
          accessTokenLoader: () async => 'token',
          onUnauthorized: () async {},
          nameLookup: _names,
        ),
      );

  Future<void> pumpDetail(WidgetTester tester, MockClient client) =>
      pumpLocalized(
        tester,
        RuleDetailScreen(
          ruleId: 'r1',
          service: RulesService(client: client),
          accessTokenLoader: () async => 'token',
          onUnauthorized: () async {},
          nameLookup: _names,
        ),
      );

  testWidgets('lists rules with name or generated title and status',
      (tester) async {
    await pumpList(
      tester,
      server(rules: [
        _rule('r1', name: 'Coffee runs'),
        _rule('r2', active: false),
      ]),
    );

    expect(find.text('Create or reorder rules on the web'), findsOneWidget);
    expect(find.text('Coffee runs'), findsOneWidget);
    expect(find.text('If Name contains “Coffee”'), findsOneWidget);
    expect(find.text('Set category to Food · Transactions · Active'),
        findsOneWidget);
    expect(find.text('Set category to Food · Transactions · Inactive'),
        findsOneWidget);
  });

  testWidgets('tapping a rule opens its detail', (tester) async {
    await pumpList(tester, server(rules: [_rule('r1', name: 'Coffee runs')]));
    await tester.tap(find.text('Coffee runs'));
    await tester.pumpAndSettle();
    expect(find.byType(RuleDetailScreen), findsOneWidget);
    expect(find.text('Conditions'), findsOneWidget);
  });

  testWidgets('empty state', (tester) async {
    await pumpList(tester, server(rules: []));
    expect(find.text('No rules yet'), findsOneWidget);
  });

  testWidgets('error state', (tester) async {
    await pumpList(tester, MockClient((_) async => http.Response('{}', 500)));
    expect(find.text("Couldn't load rules."), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
  });

  testWidgets('detail shows conditions, actions and runs', (tester) async {
    await pumpDetail(
      tester,
      server(runs: [
        _run('success'),
        _run('failed', processed: 0, modified: 0, error: 'Boom'),
        _run('pending'),
      ]),
    );

    // The large title and its small nav-bar copy.
    expect(find.text('Coffee runs'), findsNWidgets(2));
    expect(find.byTooltip('Edit on the web'), findsOneWidget);
    expect(find.text('Transactions · Active'), findsOneWidget);
    expect(find.textContaining('Applies to transactions from'), findsOneWidget);
    expect(find.text('Name contains “Coffee”'), findsOneWidget);
    expect(find.text('Any of these match'), findsOneWidget);
    expect(find.text('Amount is more than 10'), findsOneWidget);
    expect(find.text('Category is Food'), findsOneWidget);
    expect(find.text('Set category to Food'), findsOneWidget);
    expect(find.text('Exclude from budgets and reports'), findsOneWidget);

    expect(find.text('Succeeded'), findsOneWidget);
    expect(find.text('3 of 10 transactions changed'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Boom'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('7 transactions queued'), findsOneWidget);
    expect(find.textContaining('Run by hand'), findsNWidgets(3));
  });

  testWidgets('detail lists sentences in panels with sentence-case headers',
      (tester) async {
    await pumpDetail(tester, server(runs: [_run('success')]));
    expect(find.byType(SurePanel), findsNWidgets(4));
    expect(find.byType(Card), findsNothing);
    expect(find.widgetWithText(SureSectionHeader, 'Conditions'),
        findsOneWidget);
    expect(find.widgetWithText(SureSectionHeader, 'Recent runs'),
        findsOneWidget);
  });

  testWidgets('opened from Settings, the list back link says Settings',
      (tester) async {
    await pumpLocalized(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => RulesScreen(
              service: RulesService(client: server(rules: [_rule('r1')])),
              accessTokenLoader: () async => 'token',
              onUnauthorized: () async {},
              nameLookup: _names,
            ),
          )),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SureBackButton, 'Settings'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('rule-r1')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SureBackButton, 'Rules'), findsOneWidget);
  });

  testWidgets('detail with no runs', (tester) async {
    await pumpDetail(tester, server(runs: []));
    expect(find.text("This rule hasn't run yet."), findsOneWidget);
  });

  testWidgets('a deleted rule says so and hides Edit on the web',
      (tester) async {
    await pumpDetail(tester, server(ruleStatus: 404));
    expect(find.text('This rule no longer exists.'), findsOneWidget);
    expect(find.byTooltip('Edit on the web'), findsNothing);
  });

  test('web path is the rule edit page', () {
    expect(RuleDetailScreen.webPath('r1'), '/rules/r1/edit');
  });
}
