import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/models/category.dart';
import 'package:sure_mobile/providers/server_features_provider.dart';
import 'package:sure_mobile/screens/rule_detail_screen.dart';
import 'package:sure_mobile/screens/rule_editor_sheet.dart';
import 'package:sure_mobile/screens/rules_screen.dart';
import 'package:sure_mobile/services/rules_service.dart';
import 'package:sure_mobile/utils/rule_text.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';
import 'package:sure_mobile/widgets/metadata_picker_sheet.dart';

import '../support/l10n_harness.dart';

Map<String, dynamic> _rule(String id, {String? name = 'Coffee runs'}) => {
      'id': id,
      'name': name,
      'resource_type': 'transaction',
      'active': true,
      'effective_date': '2026-03-01',
      'stop_processing': true,
      'rule_group_id': null,
      'conditions': [
        {
          'id': 'c1',
          'condition_type': 'transaction_name',
          'operator': 'like',
          'value': 'Coffee',
          'sub_conditions': [],
        },
        {
          'id': 'c2',
          'condition_type': 'compound',
          'operator': 'or',
          'value': null,
          'sub_conditions': [
            {
              'id': 'c3',
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
    };

const _meta = {'current_page': 1, 'total_pages': 1, 'per_page': 100};

String? _names(RuleValueKind kind, String id) =>
    kind == RuleValueKind.category && id == 'cat1' ? 'Food' : null;

final _choices = RuleEditorChoices(
  categories: [
    Category(id: 'cat1', name: 'Food'),
    Category(id: 'cat2', name: 'Travel'),
  ],
  merchants: const [PickerOption(id: 'm1', label: 'Blue Bottle')],
  tags: const [
    PickerOption(id: 't1', label: 'Coffee'),
    PickerOption(id: 't2', label: 'Work'),
  ],
  accounts: const [PickerOption(id: 'acc1', label: 'Checking')],
);

/// Records writes ("METHOD path") and their decoded bodies.
class _Server {
  _Server({
    this.saveStatus = 200,
    this.warnings = const [],
    this.applyRunning = false,
    this.saveError,
  });

  final int saveStatus;
  final List<String> warnings;
  final bool applyRunning;
  final Map<String, dynamic>? saveError;
  final writes = <String>[];
  final bodies = <dynamic>[];
  int runsLoads = 0;

  late final client = MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'GET') {
      if (path == '/api/v1/rules') {
        return http.Response(
            jsonEncode({
              'data': [_rule('r1')],
              'meta': _meta,
            }),
            200);
      }
      if (path == '/api/v1/rule_runs') {
        runsLoads++;
        return http.Response(jsonEncode({'data': [], 'meta': _meta}), 200);
      }
      final id = path.split('/').last;
      return http.Response(
          jsonEncode({'data': _rule(id, name: id == 'r2' ? 'Copy' : 'Coffee runs')}),
          200);
    }
    writes.add('${request.method} $path');
    final body = request.body.isEmpty ? null : jsonDecode(request.body);
    bodies.add(body);
    if (request.method == 'DELETE') return http.Response('', 204);
    if (path.endsWith('/apply')) {
      if (applyRunning && body is Map && body['confirm'] == true) {
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
                'transactions_processed': 12,
                'transactions_modified': 4,
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
    }
    if (saveError != null) {
      return http.Response(jsonEncode(saveError), saveStatus);
    }
    final saved = request.method == 'POST' ? 'r2' : 'r1';
    return http.Response(
        jsonEncode({'data': _rule(saved), 'warnings': warnings}),
        request.method == 'POST' ? 201 : 200);
  });
}

ServerFeaturesProvider _features(bool on) => ServerFeaturesProvider()
  ..debugSet(on ? {ServerFeaturesProvider.rulesWrite} : {});

Future<void> _pumpList(WidgetTester tester, _Server server,
        {bool feature = true}) =>
    pumpLocalized(
      tester,
      ChangeNotifierProvider<ServerFeaturesProvider>.value(
        value: _features(feature),
        child: RulesScreen(
          service: RulesService(client: server.client),
          accessTokenLoader: () async => 'token',
          onUnauthorized: () async {},
          nameLookup: _names,
          editorChoices: _choices,
        ),
      ),
      logicalHeight: 1400,
    );

Future<void> _pumpDetail(WidgetTester tester, _Server server,
        {bool feature = true}) =>
    pumpLocalized(
      tester,
      ChangeNotifierProvider<ServerFeaturesProvider>.value(
        value: _features(feature),
        child: RuleDetailScreen(
          ruleId: 'r1',
          service: RulesService(client: server.client),
          accessTokenLoader: () async => 'token',
          onUnauthorized: () async {},
          nameLookup: _names,
          editorChoices: _choices,
        ),
      ),
      logicalHeight: 1400,
    );

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The pill whose key starts with [prefix], [index]th in tree order.
Finder _pill(String prefix, [int index = 0]) => find
    .byWidgetPredicate((w) =>
        w is RuleEditorPill &&
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith(prefix))
    .at(index);

Future<void> _enterValue(WidgetTester tester, Finder pill, String text) async {
  await _tap(tester, pill);
  await tester.enterText(find.byKey(const ValueKey('ruleValueField')), text);
  await _tap(tester, find.byKey(const ValueKey('ruleValueDone')));
}

Future<void> _choose(WidgetTester tester, String label) =>
    _tap(tester, find.text(label).last);

void main() {
  group('without rules.write', () {
    testWidgets('the list keeps the web row and has no +', (tester) async {
      await _pumpList(tester, _Server(), feature: false);
      expect(find.text('Create or reorder rules on the web'), findsOneWidget);
      expect(find.byKey(const ValueKey('rulesAdd')), findsNothing);
    });

    testWidgets('the detail stays read-only with the web link',
        (tester) async {
      await _pumpDetail(tester, _Server(), feature: false);
      expect(find.byTooltip('Edit on the web'), findsOneWidget);
      expect(find.text('Apply to past transactions'), findsNothing);
      expect(find.byKey(const ValueKey('ruleEdit')), findsNothing);
    });
  });

  group('with rules.write', () {
    testWidgets('the list offers + and renames the web row', (tester) async {
      await _pumpList(tester, _Server());
      expect(find.text('Reorder rules on the web'), findsOneWidget);
      expect(find.byKey(const ValueKey('rulesAdd')), findsOneWidget);
    });

    testWidgets('creates a rule from pills and shows save warnings',
        (tester) async {
      final server = _Server(warnings: ['The rule was switched off.']);
      await _pumpList(tester, server);
      await _tap(tester, find.byKey(const ValueKey('rulesAdd')));

      expect(find.text('New rule'), findsWidgets);
      // The default condition: Name contains [Enter a value].
      expect(find.text('Name'), findsWidgets);
      expect(find.text('contains'), findsOneWidget);
      await _enterValue(tester, _pill('ruleValue-'), 'Coffee');
      expect(find.text('“Coffee”'), findsOneWidget);

      // The default action: Set category [Choose…].
      expect(find.text('Set category'), findsOneWidget);
      await _tap(tester, _pill('ruleActionValue-'));
      await _choose(tester, 'Food');
      await tester.enterText(
          find.byKey(const ValueKey('ruleEditorName')), 'Coffee shops');
      await _tap(tester, find.byKey(const ValueKey('ruleEditorSave')));

      expect(server.writes, ['POST /api/v1/rules']);
      expect(server.bodies.single, {
        'rule': {
          'name': 'Coffee shops',
          'resource_type': 'transaction',
          'active': true,
          'conditions': [
            {
              'condition_type': 'transaction_name',
              'operator': 'like',
              'value': 'Coffee',
            },
          ],
          'actions': [
            {'action_type': 'set_transaction_category', 'value': 'cat1'},
          ],
        },
      });
      expect(find.text('Rule saved'), findsOneWidget);
      expect(find.widgetWithText(SureBanner, 'The rule was switched off.'),
          findsOneWidget);
    });

    testWidgets('missing values block saving', (tester) async {
      final server = _Server();
      await _pumpList(tester, server);
      await _tap(tester, find.byKey(const ValueKey('rulesAdd')));
      await _tap(tester, find.byKey(const ValueKey('ruleEditorSave')));
      expect(find.text('Fill in every value, or remove the row.'),
          findsOneWidget);
      expect(server.writes, isEmpty);
    });

    testWidgets('a field change limits the operators to its own',
        (tester) async {
      await _pumpList(tester, _Server());
      await _tap(tester, find.byKey(const ValueKey('rulesAdd')));
      await _tap(tester, _pill('ruleField-'));
      await _choose(tester, 'Type');
      // TransactionType offers only "=".
      expect(find.text('is'), findsOneWidget);
      await _tap(tester, _pill('ruleOperator-'));
      expect(find.text('contains'), findsNothing);
      expect(find.text('is not'), findsNothing);
      await _choose(tester, 'is');

      await _tap(tester, _pill('ruleField-'));
      await _choose(tester, 'Amount');
      await _tap(tester, _pill('ruleOperator-'));
      expect(find.text('is more than'), findsOneWidget);
      expect(find.text('contains'), findsNothing);
    });

    testWidgets('builds a compound any-group with an amount', (tester) async {
      final server = _Server();
      await _pumpList(tester, server);
      await _tap(tester, find.byKey(const ValueKey('rulesAdd')));
      // Drop the default condition, add a group instead.
      await _tap(tester, find.byTooltip('Remove').first);
      await _tap(tester, find.byKey(const ValueKey('ruleAddGroup')));
      await _tap(tester, _pill('ruleGroup-'));
      await _choose(tester, 'Any of these match');

      await _tap(tester, _pill('ruleField-'));
      await _choose(tester, 'Amount');
      await _tap(tester, _pill('ruleOperator-'));
      await _choose(tester, 'is more than');
      await _enterValue(tester, _pill('ruleValue-'), '25.50');

      // A second sub-condition: Merchant is Blue Bottle.
      await _tap(tester, find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('ruleGroupAdd-')));
      await _tap(tester, _pill('ruleField-', 1));
      await _choose(tester, 'Merchant');
      await _tap(tester, _pill('ruleValue-', 1));
      await _choose(tester, 'Blue Bottle');

      // Action: change to Add tags with two tags.
      await _tap(tester, _pill('ruleAction-'));
      await _choose(tester, 'Add tags');
      await _tap(tester, _pill('ruleActionValue-'));
      await tester.tap(find.text('Coffee').last);
      await tester.tap(find.text('Work').last);
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Done').last);
      await _tap(tester, find.byKey(const ValueKey('ruleEditorSave')));

      final rule = (server.bodies.single as Map)['rule'] as Map;
      expect(rule['conditions'], [
        {
          'condition_type': 'compound',
          'operator': 'or',
          'value': null,
          'sub_conditions': [
            {
              'condition_type': 'transaction_amount',
              'operator': '>',
              'value': '25.5',
            },
            {
              'condition_type': 'transaction_merchant',
              'operator': '=',
              'value': 'm1',
            },
          ],
        },
      ]);
      expect(rule['actions'], [
        {'action_type': 'set_transaction_tags', 'value': 't1,t2'},
      ]);
    });

    testWidgets('edit sends the full lists, minus what was removed',
        (tester) async {
      final server = _Server();
      await _pumpDetail(tester, server);
      await _tap(tester, find.byKey(const ValueKey('ruleEdit')));
      expect(find.text('Edit rule'), findsOneWidget);
      expect(find.text('“Coffee”'), findsOneWidget);
      expect(find.text('Any of these match'), findsWidgets);

      // Remove the compound group (the second top-level ✕: name row, group).
      await _tap(tester, find.byTooltip('Remove').at(1));
      await _enterValue(tester, _pill('ruleValue-'), 'Latte');
      await tester.tap(find.byKey(const ValueKey('ruleEditorActive')));
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('ruleEditorSave')));

      expect(server.writes, ['PATCH /api/v1/rules/r1']);
      expect(server.bodies.single, {
        'rule': {
          'name': 'Coffee runs',
          'resource_type': 'transaction',
          'active': false,
          'conditions': [
            {
              'id': 'c1',
              'condition_type': 'transaction_name',
              'operator': 'like',
              'value': 'Latte',
            },
          ],
          'actions': [
            {
              'id': 'a1',
              'action_type': 'set_transaction_category',
              'value': 'cat1',
            },
          ],
        },
      });
      expect(find.text('Rule saved'), findsOneWidget);
    });

    testWidgets('save errors show the server message and read-only scope',
        (tester) async {
      final server = _Server(saveStatus: 403, saveError: {
        'error': 'insufficient_scope',
        'message': 'This action requires the read_write scope',
      });
      await _pumpDetail(tester, server);
      await _tap(tester, find.byKey(const ValueKey('ruleEdit')));
      await _tap(tester, find.byKey(const ValueKey('ruleEditorSave')));
      expect(
          find.text('This sign-in can only view data. Sign in again with '
              'full access to make changes.'),
          findsOneWidget);
      expect(find.text('Edit rule'), findsOneWidget);
    });

    testWidgets('duplicate posts a copy without ids and opens it',
        (tester) async {
      final server = _Server();
      await _pumpDetail(tester, server);
      await _tap(tester, find.byKey(const ValueKey('ruleDuplicate')));
      expect(find.text('New rule'), findsOneWidget);
      final name = tester.widget<TextFormField>(
          find.byKey(const ValueKey('ruleEditorName')));
      expect(name.controller!.text, 'Coffee runs (copy)');
      await _tap(tester, find.byKey(const ValueKey('ruleEditorSave')));

      expect(server.writes, ['POST /api/v1/rules']);
      final rule = (server.bodies.single as Map)['rule'] as Map;
      expect(rule['name'], 'Coffee runs (copy)');
      expect(rule['effective_date'], '2026-03-01');
      expect(rule['stop_processing'], true);
      expect(jsonEncode(rule).contains('"id"'), isFalse);
      expect((rule['conditions'] as List).last['sub_conditions'], hasLength(1));
      // The copy replaced the screen.
      expect(find.text('Copy'), findsWidgets);
    });

    testWidgets('delete asks first, then sends DELETE', (tester) async {
      final server = _Server();
      await _pumpDetail(tester, server);
      await _tap(tester, find.byKey(const ValueKey('ruleDelete')));
      expect(find.text('Delete this rule?'), findsOneWidget);
      await _tap(tester, find.text('Cancel'));
      expect(server.writes, isEmpty);

      await _tap(tester, find.byKey(const ValueKey('ruleDelete')));
      await _tap(tester, find.byKey(const ValueKey('ruleDeleteConfirm')));
      expect(server.writes, ['DELETE /api/v1/rules/r1']);
      expect(find.text('Rule deleted'), findsOneWidget);
    });

    testWidgets('apply confirms with the server details incl. AI cost',
        (tester) async {
      final server = _Server();
      await _pumpDetail(tester, server);
      final runsBefore = server.runsLoads;
      await _tap(tester, find.byKey(const ValueKey('ruleApply')));

      expect(server.bodies.single, {});
      expect(find.text('Apply this rule?'), findsOneWidget);
      expect(find.textContaining('It will change 12 transactions.'),
          findsOneWidget);
      expect(find.textContaining('2 active rules run before it.'),
          findsOneWidget);
      expect(find.textContaining(r'Uses AI categorization · about $0.0123'),
          findsOneWidget);

      await _tap(tester, find.byKey(const ValueKey('ruleApplyConfirm')));
      expect(server.writes,
          ['POST /api/v1/rules/r1/apply', 'POST /api/v1/rules/r1/apply']);
      expect(server.bodies.last, {'confirm': true});
      expect(find.text('Changed 4 transactions'), findsOneWidget);
      expect(server.runsLoads, greaterThan(runsBefore));
    });

    testWidgets('cancelling the confirmation applies nothing',
        (tester) async {
      final server = _Server();
      await _pumpDetail(tester, server);
      await _tap(tester, find.byKey(const ValueKey('ruleApply')));
      await _tap(tester, find.text('Cancel'));
      expect(server.writes, ['POST /api/v1/rules/r1/apply']);
      expect(find.textContaining('Changed'), findsNothing);
    });

    testWidgets('a running rule (409) says to try again', (tester) async {
      final server = _Server(applyRunning: true);
      await _pumpDetail(tester, server);
      await _tap(tester, find.byKey(const ValueKey('ruleApply')));
      await _tap(tester, find.byKey(const ValueKey('ruleApplyConfirm')));
      expect(find.text('Another rule is running. Try again in a moment.'),
          findsOneWidget);
    });
  });

  testWidgets('the editor fits a 320 pt wide screen', (tester) async {
    await pumpLocalized(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showRuleEditorSheet(
            context,
            save: (_) async => {'success': false},
            choices: _choices,
          ),
          child: const Text('open'),
        ),
      ),
    );
    tester.view.physicalSize = const Size(320 * 3, 900 * 3);
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('ruleAddGroup')));
    await _tap(tester, _pill('ruleAction-'));
    await _choose(tester, 'Mark as transfer or payment to');
    expect(tester.takeException(), isNull);
  });
}
