import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/models/rule.dart';
import 'package:sure_mobile/providers/server_features_provider.dart';
import 'package:sure_mobile/screens/rule_editor_sheet.dart';
import 'package:sure_mobile/screens/rules_screen.dart';
import 'package:sure_mobile/services/rules_service.dart';
import 'package:sure_mobile/utils/rule_catalog.dart';
import 'package:sure_mobile/utils/rule_layout.dart';
import 'package:sure_mobile/widgets/metadata_picker_sheet.dart';

import '../support/l10n_harness.dart';

Map<String, dynamic> _rule(String id, String name, {String? group}) => {
      'id': id,
      'name': name,
      'resource_type': 'transaction',
      'active': true,
      'effective_date': null,
      'position': 1,
      'stop_processing': false,
      'rule_group_id': group,
      'rule_group': group == null
          ? null
          : {'id': group, 'name': group == 'g1' ? 'Bills' : 'Fun'},
      'conditions': [
        {
          'id': 'c-$id',
          'condition_type': 'transaction_name',
          'operator': 'like',
          'value': name,
          'sub_conditions': [],
        },
      ],
      'actions': [
        {'id': 'a-$id', 'action_type': 'exclude_transaction', 'value': null},
      ],
    };

const _meta = {'current_page': 1, 'total_pages': 1, 'per_page': 100};

const _catalog = {
  'resource_type': 'transaction',
  'ai_available': true,
  'conditions': [
    {
      'key': 'transaction_name',
      'label': 'Name',
      'type': 'text',
      'operators': [
        {'key': 'like', 'label': 'contains', 'requires_value': true},
        {'key': 'is_null', 'label': 'is empty', 'requires_value': false},
      ],
      'options': null,
      'number_step': null,
    },
    {
      'key': 'transaction_amount',
      'label': 'Amount',
      'type': 'number',
      'operators': [
        {'key': '=', 'label': 'is', 'requires_value': true},
        {'key': '>', 'label': 'more than', 'requires_value': true},
      ],
      'options': null,
      'number_step': 0.01,
    },
    {
      'key': 'transaction_category',
      'label': 'Category',
      'type': 'select',
      'operators': [
        {'key': '=', 'label': 'is', 'requires_value': true},
      ],
      'options': [
        {'value': 'cat1', 'label': 'Rent & bills'},
        {'value': 'cat2', 'label': 'Utilities'},
      ],
      'number_step': null,
    },
  ],
  'actions': [
    {
      'key': 'set_transaction_category',
      'label': 'Set transaction category',
      'value_type': 'select',
      'options': [
        {'value': 'cat1', 'label': 'Rent & bills'},
        {'value': 'cat2', 'label': 'Utilities'},
      ],
      'requires_ai': false,
      'available': true,
    },
    {
      'key': 'split_transaction',
      'label': 'Split transaction',
      'value_type': 'split',
      'options': null,
      'requires_ai': false,
      'available': true,
    },
    {
      'key': 'auto_categorize',
      'label': 'Auto categorize',
      'value_type': 'function',
      'options': null,
      'requires_ai': true,
      'available': true,
    },
    {
      'key': 'auto_detect_merchants',
      'label': 'Auto detect merchants',
      'value_type': 'function',
      'options': null,
      'requires_ai': true,
      'available': false,
    },
  ],
};

/// Records requests ("METHOD path?query") and decoded bodies.
class _Server {
  _Server({this.grouped = true, this.reorderError = false});

  final bool grouped;
  final bool reorderError;
  final requests = <String>[];
  final bodies = <String, dynamic>{};
  int listLoads = 0;
  final groups = <Map<String, dynamic>>[
    {'id': 'g1', 'name': 'Bills', 'position': 1, 'rules_count': 2},
  ];

  List<Map<String, dynamic>> get rules => grouped
      ? [
          _rule('r1', 'Rent', group: 'g1'),
          _rule('r2', 'Power', group: 'g1'),
          _rule('r3', 'Coffee'),
        ]
      : [_rule('r1', 'Rent'), _rule('r3', 'Coffee')];

  late final client = MockClient((request) async {
    final path = request.url.path;
    final query = request.url.query;
    final key = '${request.method} $path';
    requests.add(query.isEmpty || request.method != 'GET' || path == '/api/v1/rules'
        ? key
        : '$key?$query');
    final body = request.body.isEmpty ? null : jsonDecode(request.body);
    if (request.method != 'GET') bodies[key] = body;

    switch (key) {
      case 'GET /api/v1/rules':
        listLoads++;
        return http.Response(jsonEncode({'data': rules, 'meta': _meta}), 200);
      case 'GET /api/v1/rules/catalog':
        return http.Response(jsonEncode(_catalog), 200);
      case 'GET /api/v1/rule_groups':
        return http.Response(jsonEncode({'data': groups}), 200);
      case 'POST /api/v1/rule_groups':
        final group = {
          'id': 'g2',
          'name': (body as Map)['rule_group']['name'],
          'position': 2,
          'rules_count': 0,
        };
        groups.add(group);
        return http.Response(jsonEncode({'data': group}), 201);
      case 'PATCH /api/v1/rules/reorder':
        if (reorderError) {
          return http.Response(
              jsonEncode({
                'error': 'validation_failed',
                'message': 'rules of the same group must be listed together',
              }),
              422);
        }
        final ids = ((body as Map)['rule_ids'] as List).cast<String>();
        final byId = {for (final r in rules) r['id']: r};
        return http.Response(
            jsonEncode({'rules': [for (final id in ids) byId[id]]}), 200);
      case 'POST /api/v1/rules/apply_all':
        if (body is Map && body['confirm'] == true) {
          return http.Response(
              jsonEncode({
                'data': {'status': 'queued', 'rule_count': 3},
              }),
              202);
        }
        return http.Response(
            jsonEncode({
              'error': 'confirmation_required',
              'message': 'Send confirm: true to apply them.',
              'confirmation': {
                'rule_count': 3,
                'affected_resource_count': 40,
                'auto_categorize': false,
                'ai_model': null,
                'estimated_ai_cost': null,
              },
            }),
            422);
      case 'POST /api/v1/rules':
        return http.Response(
            jsonEncode({'data': _rule('r9', 'New'), 'warnings': []}), 201);
    }
    if (request.method == 'PATCH' && path.startsWith('/api/v1/rule_groups/')) {
      final group = groups.firstWhere((g) => g['id'] == path.split('/').last);
      group['name'] = (body as Map)['rule_group']['name'];
      return http.Response(jsonEncode({'data': group}), 200);
    }
    if (request.method == 'DELETE' && path.startsWith('/api/v1/rule_groups/')) {
      groups.removeWhere((g) => g['id'] == path.split('/').last);
      return http.Response('', 204);
    }
    return http.Response(jsonEncode({'error': 'not_found'}), 404);
  });
}

const _all = {
  ServerFeaturesProvider.rulesWrite,
  ServerFeaturesProvider.rulesGroups,
  ServerFeaturesProvider.rulesReorder,
  ServerFeaturesProvider.rulesApplyAll,
  ServerFeaturesProvider.rulesCatalog,
};

Future<void> _pumpList(WidgetTester tester, _Server server,
        {Set<String> features = _all}) =>
    pumpLocalized(
      tester,
      ChangeNotifierProvider<ServerFeaturesProvider>.value(
        value: ServerFeaturesProvider()..debugSet(features),
        child: RulesScreen(
          service: RulesService(client: server.client),
          accessTokenLoader: () async => 'token',
          onUnauthorized: () async {},
          nameLookup: (kind, id) => null,
          editorChoices: const RuleEditorChoices(),
        ),
      ),
      logicalHeight: 1600,
    );

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _pill(String prefix, [int index = 0]) => find
    .byWidgetPredicate((w) =>
        w is RuleEditorPill &&
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith(prefix))
    .at(index);

Future<void> _choose(WidgetTester tester, String label) =>
    _tap(tester, find.text(label).last);

/// Adds a split row through its sheet.
Future<void> _addSplit(
    WidgetTester tester, String name, String share, String? category) async {
  await _tap(tester, find.byKey(const ValueKey('ruleSplitAdd')));
  await tester.enterText(find.byKey(const ValueKey('ruleSplitName')), name);
  await tester.enterText(find.byKey(const ValueKey('ruleSplitShare')), share);
  if (category != null) {
    await _tap(tester, find.byKey(const ValueKey('ruleSplitCategory')));
    await _choose(tester, category);
  }
  await _tap(tester, find.byKey(const ValueKey('ruleSplitDone')));
}

bool _saveEnabled(WidgetTester tester) => tester
    .widget<TextButton>(find.byKey(const ValueKey('ruleEditorSave')))
    .onPressed != null;

void main() {
  setUp(RulesService.clearCatalogCache);

  test('ruleBlocks keeps groups together where their first rule is', () {
    final rules = [
      Rule.fromJson(_rule('a', 'A')),
      Rule.fromJson(_rule('b', 'B', group: 'g1')),
      Rule.fromJson(_rule('c', 'C', group: 'g1')),
      Rule.fromJson(_rule('d', 'D')),
      Rule.fromJson(_rule('e', 'E', group: 'g2')),
    ];
    final blocks = ruleBlocks(rules);
    expect(blocks.map((b) => b.key), ['ungrouped', 'group:g1', 'group:g2']);
    expect(blocks.first.rules.map((r) => r.id), ['a', 'd']);
    expect(blocks[1].groupName, 'Bills');
    expect(ruleBlockIds(blocks), ['a', 'd', 'b', 'c', 'e']);
  });

  test('catalog parsing maps value types, valueless operators and AI', () {
    final catalog = RuleEditorCatalog.fromJson(
        jsonDecode(jsonEncode(_catalog)) as Map<String, dynamic>);
    expect(catalog.fromServer, isTrue);
    final name = catalog.condition('transaction_name')!;
    expect(name.needsValue('like'), isTrue);
    expect(name.needsValue('is_null'), isFalse);
    expect(catalog.condition('transaction_category')!.options!.first.label,
        'Rent & bills');
    expect(catalog.action('auto_categorize')!.offeredForNew, isTrue);
    expect(catalog.action('auto_detect_merchants')!.offeredForNew, isFalse);
    expect(catalog.splitOptions('category').map((o) => o.value),
        ['cat1', 'cat2']);
  });

  group('without the round-two features', () {
    testWidgets('the list stays flat with the web reorder row',
        (tester) async {
      final server = _Server();
      await _pumpList(tester, server,
          features: {ServerFeaturesProvider.rulesWrite});
      expect(find.text('Reorder rules on the web'), findsOneWidget);
      expect(find.byKey(const ValueKey('rulesReorder')), findsNothing);
      expect(find.text('Apply all rules'), findsNothing);
      expect(find.text('Manage groups'), findsNothing);
      expect(find.text('Bills'), findsNothing);
      expect(find.text('Ungrouped'), findsNothing);

      // The editor keeps the hand-written catalog and has no Group row.
      await _tap(tester, find.byKey(const ValueKey('rulesAdd')));
      expect(server.requests.where((r) => r.contains('catalog')), isEmpty);
      expect(find.byKey(const ValueKey('ruleEditorGroup')), findsNothing);
    });
  });

  group('rules.groups', () {
    testWidgets('sections by group with Ungrouped, and Manage groups',
        (tester) async {
      await _pumpList(tester, _Server());
      expect(find.byKey(const ValueKey('ruleSection-group:g1')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('ruleSection-ungrouped')),
          findsOneWidget);
      expect(find.text('Bills'), findsOneWidget);
      expect(find.text('Ungrouped'), findsOneWidget);
      expect(find.text('Manage groups'), findsOneWidget);
      final bills = tester.getTopLeft(find.text('Bills')).dy;
      final ungrouped = tester.getTopLeft(find.text('Ungrouped')).dy;
      expect(bills, lessThan(tester.getTopLeft(find.text('Rent')).dy));
      expect(ungrouped, greaterThan(tester.getTopLeft(find.text('Power')).dy));
    });

    testWidgets('no Ungrouped header without groups', (tester) async {
      await _pumpList(tester, _Server(grouped: false));
      expect(find.text('Ungrouped'), findsNothing);
      expect(find.text('Rent'), findsOneWidget);
    });

    testWidgets('manage groups adds, renames and deletes', (tester) async {
      final server = _Server();
      await _pumpList(tester, server);
      await _tap(tester, find.text('Manage groups'));
      expect(find.text('Groups'), findsWidgets);
      expect(find.text('2 rules'), findsOneWidget);

      await _tap(tester, find.byKey(const ValueKey('ruleGroupAdd')));
      await tester.enterText(
          find.byKey(const ValueKey('ruleGroupName')), 'Subscriptions');
      await _tap(tester, find.byKey(const ValueKey('ruleGroupSave')));
      expect(server.bodies['POST /api/v1/rule_groups'], {
        'rule_group': {'name': 'Subscriptions'},
      });
      expect(find.text('Subscriptions'), findsOneWidget);

      await _tap(tester, find.text('Bills'));
      expect(find.text('Rename group'), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('ruleGroupName')), 'Bills & rent');
      await _tap(tester, find.byKey(const ValueKey('ruleGroupSave')));
      expect(server.bodies['PATCH /api/v1/rule_groups/g1'], {
        'rule_group': {'name': 'Bills & rent'},
      });

      // Swipe to delete, with a confirm that the rules stay.
      await tester.drag(find.text('Bills & rent'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('ruleGroup-g1')),
          matching: find.text('Delete')));
      await tester.pumpAndSettle();
      expect(find.text('Its rules stay, without a group.'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('ruleGroupDeleteConfirm')));
      expect(server.requests, contains('DELETE /api/v1/rule_groups/g1'));
      expect(find.text('Group deleted'), findsOneWidget);
      expect(find.text('Bills & rent'), findsNothing);
    });

    testWidgets('the editor picks a group or names a new one',
        (tester) async {
      final server = _Server();
      await _pumpList(tester, server);
      await _tap(tester, find.byKey(const ValueKey('rulesAdd')));
      expect(find.byKey(const ValueKey('ruleEditorGroup')), findsOneWidget);

      await _tap(tester, find.byKey(const ValueKey('ruleEditorGroup')));
      await _choose(tester, 'New group…');
      await tester.enterText(
          find.byKey(const ValueKey('ruleGroupName')), 'Travel');
      await _tap(tester, find.byKey(const ValueKey('ruleGroupSave')));
      expect(find.text('Travel'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('ruleEditorName')), 'X');
      await tester.tap(_pill('ruleValue-'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('ruleValueField')), 'X');
      await _tap(tester, find.byKey(const ValueKey('ruleValueDone')));
      await _tap(tester, _pill('ruleActionValue-'));
      await _choose(tester, 'Utilities');
      await _tap(tester, find.byKey(const ValueKey('ruleEditorSave')));
      final rule = (server.bodies['POST /api/v1/rules'] as Map)['rule'] as Map;
      expect(rule['new_rule_group_name'], 'Travel');
      expect(rule.containsKey('rule_group_id'), isFalse);
      expect(rule['actions'], [
        {'action_type': 'set_transaction_category', 'value': 'cat2'},
      ]);
    });
  });

  group('rules.reorder', () {
    testWidgets('Edit replaces the web row; Done without moves sends nothing',
        (tester) async {
      final server = _Server();
      await _pumpList(tester, server);
      expect(find.text('Reorder rules on the web'), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('rulesReorder')));
      expect(find.byKey(const ValueKey('reorderRuleHandle-r1')), findsOneWidget);
      expect(find.byKey(const ValueKey('reorderBlockHandle-group:g1')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('rulesAdd')), findsNothing);
      await _tap(tester, find.text('Done'));
      expect(server.requests.where((r) => r.startsWith('PATCH')), isEmpty);
      expect(find.byKey(const ValueKey('reorderRuleHandle-r1')), findsNothing);
    });

    testWidgets('dragging a rule within its group sends the full id list',
        (tester) async {
      final server = _Server();
      await _pumpList(tester, server);
      await _tap(tester, find.byKey(const ValueKey('rulesReorder')));

      final handle = find.byKey(const ValueKey('reorderRuleHandle-r1'));
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, 12));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      await _tap(tester, find.text('Done'));
      expect(server.bodies['PATCH /api/v1/rules/reorder'], {
        'rule_ids': ['r2', 'r1', 'r3'],
      });
    });

    testWidgets('dragging a group moves its rules as one block',
        (tester) async {
      final server = _Server();
      await _pumpList(tester, server);
      await _tap(tester, find.byKey(const ValueKey('rulesReorder')));

      final handle =
          find.byKey(const ValueKey('reorderBlockHandle-group:g1'));
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < 16; i++) {
        await gesture.moveBy(const Offset(0, 15));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      await _tap(tester, find.text('Done'));
      expect(server.bodies['PATCH /api/v1/rules/reorder'], {
        'rule_ids': ['r3', 'r1', 'r2'],
      });
    });

    testWidgets('a 422 shows the message and reloads', (tester) async {
      final server = _Server(reorderError: true);
      await _pumpList(tester, server);
      await _tap(tester, find.byKey(const ValueKey('rulesReorder')));
      final handle = find.byKey(const ValueKey('reorderRuleHandle-r1'));
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, 12));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      final loads = server.listLoads;
      await _tap(tester, find.text('Done'));
      expect(find.text('rules of the same group must be listed together'),
          findsOneWidget);
      expect(server.listLoads, loads + 1);
    });
  });

  group('rules.apply_all', () {
    testWidgets('confirms with the server counts, then queues',
        (tester) async {
      final server = _Server();
      await _pumpList(tester, server);
      await _tap(tester, find.text('Apply all rules'));
      expect(server.bodies['POST /api/v1/rules/apply_all'], {});
      expect(find.text('Apply all rules?'), findsOneWidget);
      expect(find.textContaining('Runs all 3 rules'), findsOneWidget);
      expect(find.textContaining('It will change 40 transactions.'),
          findsOneWidget);
      final loads = server.listLoads;
      await _tap(tester, find.byKey(const ValueKey('rulesApplyAllConfirm')));
      expect(server.bodies['POST /api/v1/rules/apply_all'], {'confirm': true});
      expect(find.text('Queued 3 rules'), findsOneWidget);
      expect(server.listLoads, loads + 1);
    });

    testWidgets('cancel queues nothing', (tester) async {
      final server = _Server();
      await _pumpList(tester, server);
      await _tap(tester, find.text('Apply all rules'));
      await _tap(tester, find.text('Cancel'));
      expect(
          server.requests.where((r) => r == 'POST /api/v1/rules/apply_all'),
          hasLength(1));
      expect(find.textContaining('Queued'), findsNothing);
    });
  });

  group('rules.catalog', () {
    testWidgets('builds the editor from the catalog, cached', (tester) async {
      final server = _Server();
      await _pumpList(tester, server);
      await _tap(tester, find.byKey(const ValueKey('rulesAdd')));
      expect(
          server.requests,
          contains('GET /api/v1/rules/catalog?'
              'resource_type=transaction&locale=en'));

      // A valueless operator hides the value pill.
      expect(_pill('ruleValue-').evaluate(), isNotEmpty);
      await _tap(tester, _pill('ruleOperator-'));
      await _choose(tester, 'is empty');
      expect(find.byWidgetPredicate((w) =>
              w is RuleEditorPill &&
              (w.key as ValueKey<String>).value.startsWith('ruleValue-')),
          findsNothing);

      // Fields come from the catalog only.
      await _tap(tester, _pill('ruleField-'));
      expect(find.text('Merchant'), findsNothing);
      await _choose(tester, 'Category');
      await _tap(tester, _pill('ruleValue-'));
      expect(find.byType(MetadataPickerSheet), findsOneWidget);
      await _choose(tester, 'Rent & bills');
      expect(find.text('Rent & bills'), findsOneWidget);

      // AI actions are offered when available.
      await _tap(tester, _pill('ruleAction-'));
      expect(find.text('Categorize with AI'), findsWidgets);
      expect(find.text('Detect merchants with AI'), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Close and reopen: no second catalog fetch.
      await _tap(tester, find.text('Cancel').first);
      await _tap(tester, find.byKey(const ValueKey('rulesAdd')));
      expect(server.requests.where((r) => r.contains('/rules/catalog')),
          hasLength(1));
    });

    testWidgets('percentage split: total 100, sent as split_rows',
        (tester) async {
      final server = _Server();
      await _pumpList(tester, server);
      await _tap(tester, find.byKey(const ValueKey('rulesAdd')));
      await _tap(tester, find.byKey(const ValueKey('ruleAddAction')));
      expect(_pill('ruleAction-', 1).evaluate(), isNotEmpty);

      // Picking a split removes the other action and says so.
      await _tap(tester, _pill('ruleAction-'));
      await _choose(tester, 'Split the transaction');
      expect(find.byWidgetPredicate((w) =>
              w is RuleEditorPill &&
              (w.key as ValueKey<String>).value.startsWith('ruleAction-')),
          findsOneWidget);
      expect(find.textContaining("only action, so the other actions"),
          findsOneWidget);
      expect(find.byKey(const ValueKey('ruleAddAction')), findsNothing);
      expect(find.text('Add 2 to 20 splits.'), findsOneWidget);
      expect(_saveEnabled(tester), isFalse);

      // "Name is empty" needs no value.
      await _tap(tester, _pill('ruleOperator-'));
      await _choose(tester, 'is empty');

      await _addSplit(tester, 'Rent', '60', 'Rent & bills');
      await _addSplit(tester, 'Power', '30', null);
      expect(find.text('Total 90%'), findsOneWidget);
      expect(find.text('The percentages must add up to 100%.'),
          findsOneWidget);
      expect(_saveEnabled(tester), isFalse);

      // Edit the second row to 40%.
      await _tap(tester, find.byKey(const ValueKey('ruleSplitRow-1')));
      await tester.enterText(find.byKey(const ValueKey('ruleSplitShare')), '40');
      await _tap(tester, find.byKey(const ValueKey('ruleSplitDone')));
      expect(find.text('Total 100%'), findsOneWidget);
      expect(_saveEnabled(tester), isTrue);

      await _tap(tester, find.byKey(const ValueKey('ruleEditorSave')));
      final rule = (server.bodies['POST /api/v1/rules'] as Map)['rule'] as Map;
      expect(rule['actions'], [
        {
          'action_type': 'split_transaction',
          'split_rows': [
            {
              'type': 'percentage',
              'name': 'Rent',
              'share': '60',
              'category_id': 'cat1',
              'merchant_id': null,
              'tag_ids': [],
            },
            {
              'type': 'percentage',
              'name': 'Power',
              'share': '40',
              'category_id': null,
              'merchant_id': null,
              'tag_ids': [],
            },
          ],
        },
      ]);
    });

    testWidgets('fixed split needs an exact amount condition',
        (tester) async {
      final server = _Server();
      await _pumpList(tester, server);
      await _tap(tester, find.byKey(const ValueKey('rulesAdd')));
      await _tap(tester, _pill('ruleAction-'));
      await _choose(tester, 'Split the transaction');
      await _tap(tester, find.text('Fixed'));
      await _addSplit(tester, 'Rent', '100', null);
      await _addSplit(tester, 'Power', '20', null);
      expect(find.text('Add an "Amount is" condition to save fixed splits.'),
          findsOneWidget);
      expect(_saveEnabled(tester), isFalse);

      // Make the condition "Amount is 120".
      await _tap(tester, _pill('ruleField-'));
      await _choose(tester, 'Amount');
      expect(find.text('The splits must add up to 0.00.'), findsNothing);
      await _tap(tester, _pill('ruleValue-'));
      await tester.enterText(find.byKey(const ValueKey('ruleValueField')), '150');
      await _tap(tester, find.byKey(const ValueKey('ruleValueDone')));
      expect(find.text('The splits must add up to 150.00.'), findsOneWidget);
      expect(find.text('Total 120.00 of 150.00'), findsOneWidget);

      await _tap(tester, _pill('ruleValue-'));
      await tester.enterText(find.byKey(const ValueKey('ruleValueField')), '120');
      await _tap(tester, find.byKey(const ValueKey('ruleValueDone')));
      expect(_saveEnabled(tester), isTrue);
      await _tap(tester, find.byKey(const ValueKey('ruleEditorSave')));
      final rule = (server.bodies['POST /api/v1/rules'] as Map)['rule'] as Map;
      final rows = (rule['actions'] as List).single['split_rows'] as List;
      expect(rows.map((r) => (r as Map)['type']), ['fixed', 'fixed']);
      expect(rule['conditions'], [
        {
          'condition_type': 'transaction_amount',
          'operator': '=',
          'value': '120',
        },
      ]);
    });

    testWidgets('editing a saved split prefills its rows', (tester) async {
      final split = Rule(id: 'r5', actions: [
        RuleAction(
          id: 'a5',
          actionType: 'split_transaction',
          value: jsonEncode({
            'splits': [
              {'name': 'Rent', 'type': 'fixed', 'share': '100'},
              {'name': 'Power', 'type': 'fixed', 'share': '20'},
            ],
          }),
        ),
      ]);
      Map<String, dynamic>? sent;
      await pumpLocalized(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showRuleEditorSheet(
              context,
              existing: split,
              catalog: RuleEditorCatalog.fromJson(
                  jsonDecode(jsonEncode(_catalog)) as Map<String, dynamic>),
              choices: const RuleEditorChoices(),
              save: (body) async {
                sent = body;
                return {'success': false, 'error': 'nope'};
              },
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Rent'), findsOneWidget);
      expect(find.text('Power'), findsOneWidget);
      expect(find.text('Total 120.00'), findsOneWidget);
      expect(_saveEnabled(tester), isFalse);
      expect(sent, isNull);
    });

    testWidgets('an untouched mixed split is saved back unchanged',
        (tester) async {
      final value = jsonEncode({
        'splits': [
          {'name': 'Rent', 'type': 'fixed', 'share': '100'},
          {'name': 'Rest', 'type': 'percentage', 'share': '100'},
        ],
      });
      final split = Rule(id: 'r6', name: 'Mixed', actions: [
        RuleAction(id: 'a6', actionType: 'split_transaction', value: value),
      ]);
      Map<String, dynamic>? sent;
      await pumpLocalized(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showRuleEditorSheet(
              context,
              existing: split,
              catalog: RuleEditorCatalog.fromJson(
                  jsonDecode(jsonEncode(_catalog)) as Map<String, dynamic>),
              choices: const RuleEditorChoices(),
              save: (body) async {
                sent = body;
                return {'success': false, 'error': 'nope'};
              },
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(_saveEnabled(tester), isTrue);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final body = (sent!['rule'] as Map?) ?? sent!;
      final action = (body['actions'] as List).single as Map;
      expect(action['value'], value);
      expect(action.containsKey('split_rows'), isFalse);
    });
  });

  testWidgets('the split editor and reorder mode fit 320 pt',
      (tester) async {
    final server = _Server();
    await _pumpList(tester, server);
    tester.view.physicalSize = const Size(320 * 3, 900 * 3);
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('rulesReorder')));
    expect(tester.takeException(), isNull);
    await _tap(tester, find.text('Done'));

    await _tap(tester, find.byKey(const ValueKey('rulesAdd')));
    await _tap(tester, _pill('ruleAction-'));
    await _choose(tester, 'Split the transaction');
    await _addSplit(tester, 'A rather long split name for rent', '100', null);
    await _tap(tester, find.text('Fixed'));
    expect(tester.takeException(), isNull);
  });
}
