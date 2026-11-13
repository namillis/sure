import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/models/account.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/providers/server_features_provider.dart';
import 'package:sure_mobile/screens/goal_consume_sheet.dart';
import 'package:sure_mobile/screens/goal_detail_screen.dart';
import 'package:sure_mobile/screens/goals_screen.dart';
import 'package:sure_mobile/screens/plan_screen.dart';
import 'package:sure_mobile/services/goals_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/sure_icon.dart';
import 'package:sure_mobile/widgets/sure_list_group.dart';

import '../support/goal_fixtures.dart';
import '../support/l10n_harness.dart';

/// A stateful fake of the Sure+ goals API.
class _FakeGoalsApi {
  _FakeGoalsApi(List<Map<String, dynamic>> goals)
      : goals = {for (final g in goals) g['id'] as String: g};

  final Map<String, Map<String, dynamic>> goals;
  final List<String> calls = [];
  final List<Map<String, dynamic>> bodies = [];
  http.Response? listOverride;
  http.Response? summaryOverride;
  http.Response? writeOverride;

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);

  Future<http.Response> handle(http.Request r) async {
    final path = r.url.path;
    calls.add('${r.method} $path');
    if (r.body.isNotEmpty) bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
    if (r.method == 'GET' && path == '/api/v1/goals') {
      return listOverride ?? _json({'goals': goals.values.toList()});
    }
    if (r.method == 'GET' && path == '/api/v1/goals/summary') {
      return summaryOverride ?? _json(goalsSummaryJson());
    }
    if (r.method != 'GET' && writeOverride != null) return writeOverride!;
    final parts = path.split('/'); // ['', api, v1, goals, id, pledges, pid, renew]
    if (r.method == 'POST' && path == '/api/v1/goals') {
      final body = bodies.last['goal'] as Map<String, dynamic>;
      final goal = goalJson('new', name: body['name'] as String);
      goals['new'] = goal;
      return _json(goal, 201);
    }
    final id = parts.length > 4 ? parts[4] : '';
    final goal = goals[id];
    if (goal == null) return _json({'error': 'not_found'}, 404);
    if (parts.length == 6 && r.method == 'PATCH') {
      const next = {
        'pause': 'paused',
        'resume': 'active',
        'complete': 'completed',
        'reopen': 'active',
        'archive': 'archived',
        'unarchive': 'active',
      };
      final state = next[parts[5]]!;
      goal['state'] = state;
      goal['display_status'] = state == 'active' ? goal['status'] : state;
      goal['available_actions'] = goalActionsFor(state);
      return _json(goal);
    }
    if (parts.length == 6 && parts[5] == 'consume') {
      goal['current_amount'] = '\$2,900.00';
      goal['current_amount_cents'] = 290000;
      return _json(goal, 201);
    }
    if (parts.length == 5) {
      switch (r.method) {
        case 'GET':
          return _json(goal);
        case 'PATCH':
          final body = bodies.last['goal'] as Map<String, dynamic>;
          if (body['name'] != null) goal['name'] = body['name'];
          return _json(goal);
        case 'DELETE':
          goals.remove(id);
          return _json({'message': 'Goal deleted successfully'});
      }
    }
    // Pledges.
    final pledges = goal['open_pledges'] as List;
    if (r.method == 'POST') {
      final pledge = pledgeJson('p-new',
          amount: '\$${(bodies.last['pledge'] as Map)['amount']}.00');
      goal['open_pledges'] = [pledge, ...pledges];
      goal['pending_pledges_count'] = (goal['open_pledges'] as List).length;
      return _json({'pledge': pledge, 'goal': goal}, 201);
    }
    final pledgeId = parts[6];
    final pledge = pledges.cast<Map<String, dynamic>>()
        .firstWhere((p) => p['id'] == pledgeId);
    if (r.method == 'PATCH') {
      pledge['expires_at'] = '2026-11-27T12:00:00Z';
    } else {
      goal['open_pledges'] = [
        for (final p in pledges)
          if ((p as Map)['id'] != pledgeId) p,
      ];
      goal['pending_pledges_count'] = (goal['open_pledges'] as List).length;
    }
    return _json({'pledge': pledge, 'goal': goal});
  }
}

final _accounts = [
  Account.fromJson(accountJson('acc1', 'Ally Savings', 'depository')),
  Account.fromJson(accountJson('acc2', 'Brokerage', 'investment')),
  Account.fromJson(accountJson('acc3', 'Visa', 'credit_card')),
];

void main() {
  late _FakeGoalsApi api;
  late int unauthorized;

  setUp(() {
    unauthorized = 0;
    api = _FakeGoalsApi([
      goalJson('g1',
          name: 'Emergency fund',
          callout: 'reaches goal around Mar 2027',
          pledges: [pledgeJson('p1')]),
      goalJson('g2',
          name: 'New car',
          status: 'behind',
          catchUp: '\$450.00',
          catchUpCents: 45000,
          targetDate: null,
          daysLeft: null),
      goalJson('g3', name: 'Old sofa', state: 'paused'),
      goalJson('g4', name: 'Bike', state: 'completed'),
    ]);
  });

  GoalsService service() => GoalsService(client: MockClient(api.handle));

  GoalsAuth auth() => GoalsAuth(
        accessTokenLoader: () async => 'token',
        onUnauthorized: () async => unauthorized++,
      );

  Future<void> pumpGoals(WidgetTester tester,
      {Set<String> features = const {'goals', 'goals.pledges'},
      double height = 1400}) async {
    final provider = ServerFeaturesProvider()..debugSet(features);
    await pumpLocalized(
      tester,
      ChangeNotifierProvider<ServerFeaturesProvider>.value(
        value: provider,
        child: GoalsScreen(service: service(), auth: auth(), accounts: _accounts),
      ),
      logicalHeight: height,
    );
  }

  group('Plan wiring', () {
    Future<void> pumpPlan(WidgetTester tester, Set<String> features) async {
      final provider = ServerFeaturesProvider()..debugSet(features);
      await pumpLocalized(
        tester,
        ChangeNotifierProvider<ServerFeaturesProvider>.value(
          value: provider,
          child: PlanScreen(
            budgetBuilder: (_) => const Text('budget body'),
            recurringBuilder: (_) => const Text('recurring body'),
            billsBuilder: (_) => const Text('bills body'),
            goalsBuilder: (_) => const Text('native goals'),
          ),
        ),
      );
      await tester.tap(find.text('Goals'));
      await tester.pumpAndSettle();
    }

    int webMarks(WidgetTester tester) => tester
        .widgetList<SureIcon>(find.byType(SureIcon))
        .where((icon) => icon.name == SureIcons.arrowUpRight)
        .length;

    testWidgets('with the goals feature the segment is native',
        (tester) async {
      await pumpPlan(tester, {'goals'});
      expect(find.text('native goals'), findsOneWidget);
      expect(find.text('Open on the web'), findsNothing);
      expect(webMarks(tester), 0);
    });

    testWidgets('without it the segment keeps the web link', (tester) async {
      await pumpPlan(tester, {'profile.write'});
      expect(find.text('native goals'), findsNothing);
      expect(find.textContaining('Goals live on the web'), findsOneWidget);
      expect(find.text('Open on the web'), findsOneWidget);
      expect(webMarks(tester), 1);
    });

    testWidgets('the default goals body is GoalsScreen', (tester) async {
      late Widget goals;
      await tester.pumpWidget(Builder(builder: (context) {
        goals = const PlanScreen().goalsBuilder(context);
        return const SizedBox();
      }));
      expect(goals, isA<GoalsScreen>());
    });
  });

  testWidgets('lists active cards and collapsed state rows', (tester) async {
    await pumpGoals(tester);

    expect(api.calls, ['GET /api/v1/goals']);
    expect(find.text('Active · 2'), findsOneWidget);
    expect(find.text('Emergency fund'), findsOneWidget);
    expect(find.text('Due Apr 2027 · 6 months left'), findsOneWidget);
    expect(find.text('62%'), findsNWidgets(4 - 2)); // the two active cards
    expect(find.text('\$3,100.00 of \$5,000.00'), findsNWidgets(2));
    expect(find.text('On track'), findsOneWidget);
    expect(find.text('Reaches goal around Mar 2027'), findsOneWidget);
    expect(find.text('1 pending pledge'), findsOneWidget);
    // No date, behind, catch-up line from catch_up_amount.
    expect(find.text('No date'), findsOneWidget);
    expect(find.text('Behind'), findsOneWidget);
    expect(find.text('Save \$450.00/mo to catch up'), findsOneWidget);

    expect(find.text('Paused · 1'), findsOneWidget);
    expect(find.text('Completed · 1'), findsOneWidget);
    expect(find.text('Archived · 0'), findsNothing);
    expect(find.text('Old sofa'), findsNothing);

    await tester.tap(find.text('Paused · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Old sofa'), findsOneWidget);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Bike'), findsNothing);
  });

  testWidgets('403 feature_disabled shows the preview-feature state',
      (tester) async {
    api.listOverride = http.Response(
        jsonEncode({
          'error': 'feature_disabled',
          'message': 'Preview features are not enabled for this user',
        }),
        403);
    await pumpGoals(tester);

    expect(find.byKey(const ValueKey('goalsPreviewDisabled')), findsOneWidget);
    expect(find.text('Goals are a preview feature'), findsOneWidget);
    expect(find.text('Turn on preview features on the web'), findsOneWidget);
    expect(find.text('Active · 0'), findsNothing);
  });

  testWidgets('no goals shows the empty state', (tester) async {
    api.goals.clear();
    await pumpGoals(tester);
    expect(find.text('No goals yet'), findsOneWidget);
    expect(find.text('Create your first goal'), findsOneWidget);
  });

  testWidgets('a 401 signs out', (tester) async {
    api.listOverride = http.Response('{}', 401);
    await pumpGoals(tester);
    expect(unauthorized, 1);
  });

  testWidgets('creates a goal from the + sheet', (tester) async {
    await pumpGoals(tester);
    await tester.tap(find.bySemanticsLabel('New goal'));
    await tester.pumpAndSettle();

    expect(find.text('New goal'), findsOneWidget);
    // Only Depository / Investment / Crypto accounts can fund a goal.
    expect(find.byKey(const ValueKey('goalFund-acc1')), findsOneWidget);
    expect(find.byKey(const ValueKey('goalFund-acc2')), findsOneWidget);
    expect(find.byKey(const ValueKey('goalFund-acc3')), findsNothing);

    await tester.enterText(
        find.byKey(const ValueKey('goalFormName')), 'Trip to Japan');
    await tester.enterText(
        find.byKey(const ValueKey('goalFormTarget')), '2500.50');

    // No account yet: refused client-side.
    await tester.tap(find.byKey(const ValueKey('goalFormSave')));
    await tester.pumpAndSettle();
    expect(find.text('Pick at least one account to fund this goal.'),
        findsOneWidget);
    expect(api.calls, ['GET /api/v1/goals']);

    await tester.tap(find.byKey(const ValueKey('goalFund-acc1')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('goalEarmark-acc1')), '300');
    await tester.tap(find.byKey(const ValueKey('goalFund-acc2')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('goalFormLook')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('goalIcon-plane')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('goalFormSave')));
    await tester.pumpAndSettle();

    expect(api.calls, contains('POST /api/v1/goals'));
    final body = api.bodies.firstWhere((b) => b.containsKey('goal'))['goal'];
    expect(body, {
      'name': 'Trip to Japan',
      'target_amount': '2500.5',
      'icon': 'plane',
      'kind': 'one_off',
      'account_ids': ['acc1', 'acc2'],
      'allocations': {'acc1': '300', 'acc2': ''},
    });
    expect(find.text('Goal created'), findsOneWidget);
    expect(find.text('Trip to Japan'), findsOneWidget);
  });

  testWidgets('a 422 on create stays in the sheet with the message',
      (tester) async {
    api.writeOverride = http.Response(
        jsonEncode({
          'error': 'validation_failed',
          'message': 'Goal could not be created',
          'errors': ['Name has already been taken'],
        }),
        422);
    await pumpGoals(tester);
    await tester.tap(find.bySemanticsLabel('New goal'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('goalFormName')), 'X');
    await tester.enterText(find.byKey(const ValueKey('goalFormTarget')), '10');
    await tester.tap(find.byKey(const ValueKey('goalFund-acc1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('goalFormSave')));
    await tester.pumpAndSettle();
    expect(find.text('Name has already been taken'), findsOneWidget);
    expect(find.text('New goal'), findsOneWidget);
  });

  group('detail', () {
    Future<void> openDetail(WidgetTester tester,
        {Set<String> features = const {'goals', 'goals.pledges'}}) async {
      await pumpGoals(tester, features: features);
      await tester.tap(find.text('Emergency fund'));
      await tester.pumpAndSettle();
      expect(find.byType(GoalDetailScreen), findsOneWidget);
    }

    testWidgets('shows the hero, pledges, funding and plan', (tester) async {
      await openDetail(tester);
      expect(api.calls.last, 'GET /api/v1/goals/g1');
      expect(find.byKey(const ValueKey('goalHeroAmount')), findsOneWidget);
      expect(find.text('of \$5,000.00 · due Apr 30, 2027'), findsOneWidget);
      expect(find.text('I saved toward this'), findsOneWidget);
      expect(find.text('Pending pledges'), findsOneWidget);
      expect(find.text('\$150.00 from Ally Savings'), findsOneWidget);
      expect(find.text('Confirms when it shows up · expires Nov 20'),
          findsOneWidget);
      expect(find.text('Funding accounts'), findsOneWidget);
      expect(find.text('Whole balance'), findsOneWidget);
      expect(find.text('Monthly target'), findsOneWidget);
      expect(find.text('\$400.00/mo'), findsOneWidget);
      expect(find.text('Projected completion'), findsOneWidget);
      expect(find.text('Pause or archive on the web'), findsOneWidget);
      expect(find.text('Delete goal'), findsOneWidget);
    });

    testWidgets('without goals.pledges there is no pledge button or actions',
        (tester) async {
      await openDetail(tester, features: {'goals'});
      expect(find.text('I saved toward this'), findsNothing);
      expect(find.text('\$150.00 from Ally Savings'), findsOneWidget);
      expect(find.byKey(const ValueKey('pledgeExtend-p1')), findsNothing);
    });

    testWidgets('records a pledge', (tester) async {
      await openDetail(tester);
      await tester.tap(find.byKey(const ValueKey('goalPledgeButton')));
      await tester.pumpAndSettle();
      expect(find.text('From'), findsOneWidget);
      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey('pledgeAmount')),
              matching: find.byType(EditableText)),
          '150');
      await tester.tap(find.byKey(const ValueKey('pledgeSave')));
      await tester.pumpAndSettle();

      expect(api.calls, contains('POST /api/v1/goals/g1/pledges'));
      expect(api.bodies.last, {
        'pledge': {'amount': '150', 'account_id': 'acc1'},
      });
      expect(find.text('Pledge recorded'), findsOneWidget);
      expect(find.byKey(const ValueKey('pledge-p-new')), findsOneWidget);
    });

    testWidgets('extends and cancels a pledge', (tester) async {
      await openDetail(tester);
      await tester.tap(find.byKey(const ValueKey('pledgeExtend-p1')));
      await tester.pumpAndSettle();
      expect(api.calls.last, 'PATCH /api/v1/goals/g1/pledges/p1/renew');
      expect(find.text('Confirms when it shows up · expires Nov 27'),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pledgeCancel-p1')));
      await tester.pumpAndSettle();
      expect(find.text('Cancel this pledge?'), findsOneWidget);
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(api.calls.last, isNot(startsWith('DELETE')));

      await tester.tap(find.byKey(const ValueKey('pledgeCancel-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel pledge'));
      await tester.pumpAndSettle();
      expect(api.calls.last, 'DELETE /api/v1/goals/g1/pledges/p1');
      expect(find.text('Pending pledges'), findsNothing);
    });

    testWidgets('a read-only sign-in gets the scope message', (tester) async {
      await openDetail(tester);
      api.writeOverride = http.Response(
          jsonEncode({'error': 'insufficient_scope', 'message': 'x'}), 403);
      await tester.tap(find.byKey(const ValueKey('pledgeExtend-p1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('can only view data'), findsOneWidget);
    });

    testWidgets('edits the goal', (tester) async {
      await openDetail(tester);
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('goalEdit')), 200);
      await tester.tap(find.byKey(const ValueKey('goalEdit')));
      await tester.pumpAndSettle();
      expect(find.text('Edit goal'), findsOneWidget);
      final target = tester.widget<EditableText>(find.descendant(
          of: find.byKey(const ValueKey('goalFormTarget')),
          matching: find.byType(EditableText)));
      expect(target.controller.text, '5000');

      await tester.enterText(
          find.byKey(const ValueKey('goalFormName')), 'Rainy day');
      await tester.tap(find.byKey(const ValueKey('goalFormClearDate')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('goalFormSave')));
      await tester.pumpAndSettle();

      expect(api.calls, contains('PATCH /api/v1/goals/g1'));
      final body = api.bodies.last['goal'] as Map<String, dynamic>;
      expect(body['name'], 'Rainy day');
      expect(body['target_amount'], '5000');
      expect(body['target_date'], '');
      expect(body.containsKey('kind'), false);
      expect(body['account_ids'], ['acc1']);
      expect(body['allocations'], {'acc1': ''});
      expect(find.text('Goal saved'), findsOneWidget);
      expect(find.text('Rainy day'), findsWidgets);
    });

    testWidgets('deletes the goal after confirming', (tester) async {
      await openDetail(tester);
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('goalDelete')), 200);
      await tester.tap(find.byKey(const ValueKey('goalDelete')));
      await tester.pumpAndSettle();
      expect(find.text('Delete goal?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(api.calls, contains('DELETE /api/v1/goals/g1'));
      expect(find.byType(GoalDetailScreen), findsNothing);
      expect(find.text('Goal deleted'), findsOneWidget);
      expect(find.text('Emergency fund'), findsNothing);
      expect(find.text('Active · 1'), findsOneWidget);
    });

    testWidgets('lays out at 320 px without overflow', (tester) async {
      await pumpGoals(tester);
      tester.view.physicalSize = const Size(960, 1400 * 3);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Emergency fund'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('goalPledgeButton')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('goals.summary', () {
    const withSummary = {'goals', 'goals.pledges', 'goals.summary'};

    testWidgets('shows the tiles and the saved row above the sections',
        (tester) async {
      await pumpGoals(tester, features: withSummary);
      expect(api.calls,
          containsAll(['GET /api/v1/goals', 'GET /api/v1/goals/summary']));
      expect(find.byKey(const ValueKey('goalsSummary')), findsOneWidget);
      expect(find.text('Last 30 days'), findsOneWidget);
      expect(find.text('\$420.00'), findsOneWidget);
      expect(find.text('vs \$310.00'), findsOneWidget);
      expect(find.text('Needs this month'), findsOneWidget);
      expect(find.text('\$780.00'), findsOneWidget);
      expect(find.text('1 behind'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('goalsSummaryOnTrack')),
              matching: find.text('On track')),
          findsOneWidget);
      expect(find.text('1 of 2'), findsOneWidget);
      expect(find.text('0 reached'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('\$10,000.00 / \$23,000.00'), findsOneWidget);
      // Above the sections.
      expect(
          tester.getTopLeft(find.byKey(const ValueKey('goalsSummarySaved'))).dy,
          lessThan(tester
              .getTopLeft(find.byKey(const ValueKey('goalsActiveHeader')))
              .dy));
    });

    testWidgets('without the feature there is no summary or request',
        (tester) async {
      await pumpGoals(tester);
      expect(api.calls, ['GET /api/v1/goals']);
      expect(find.byKey(const ValueKey('goalsSummary')), findsNothing);
      expect(find.text('Last 30 days'), findsNothing);
    });

    testWidgets('a failed summary is hidden and the list stays',
        (tester) async {
      api.summaryOverride = http.Response('{"error":"boom"}', 500);
      await pumpGoals(tester, features: withSummary);
      expect(find.byKey(const ValueKey('goalsSummary')), findsNothing);
      expect(find.byKey(const ValueKey('goalsLoadFailed')), findsNothing);
      expect(find.text('Emergency fund'), findsOneWidget);
    });

    testWidgets('reloads with the list after a write', (tester) async {
      await pumpGoals(tester, features: withSummary);
      int summaries() =>
          api.calls.where((c) => c == 'GET /api/v1/goals/summary').length;
      expect(summaries(), 1);
      api.summaryOverride =
          http.Response(jsonEncode(goalsSummaryJson(velocity: '\$999.00')), 200);

      await tester.tap(find.bySemanticsLabel('New goal'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('goalFormName')), 'X');
      await tester.enterText(find.byKey(const ValueKey('goalFormTarget')), '10');
      await tester.tap(find.byKey(const ValueKey('goalFund-acc1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('goalFormSave')));
      await tester.pumpAndSettle();

      expect(summaries(), 2);
      expect(find.text('\$999.00'), findsOneWidget);
    });

    testWidgets('privacy mode masks the summary amounts', (tester) async {
      tester.view.physicalSize = const Size(1170, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final provider = ServerFeaturesProvider()..debugSet(withSummary);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<PrivacyProvider>(
              create: (_) => PrivacyProvider(initialHidden: true)),
          ChangeNotifierProvider<ServerFeaturesProvider>.value(value: provider),
        ],
        child: MaterialApp(
          theme: SureTheme.light,
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: GoalsScreen(
                service: service(), auth: auth(), accounts: _accounts),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('goalsSummary')), findsOneWidget);
      expect(find.text('\$420.00'), findsNothing);
      expect(find.text('vs \$310.00'), findsNothing);
      expect(find.text('\$780.00'), findsNothing);
      expect(find.text('\$10,000.00 / \$23,000.00'), findsNothing);
      expect(find.text('1 of 2'), findsOneWidget);
    });

    for (final locale in const [Locale('en'), Locale('sv')]) {
      for (final dark in const [false, true]) {
        testWidgets(
            'fits 320 px (${locale.languageCode}, ${dark ? 'dark' : 'light'})',
            (tester) async {
          tester.view.physicalSize = const Size(960, 1400 * 3);
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          api.summaryOverride = http.Response(
              jsonEncode(goalsSummaryJson(
                  velocity: '-\$12,345,678.90', saved: '\$1,234,567.89')),
              200);
          final provider = ServerFeaturesProvider()..debugSet(withSummary);
          await tester.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<PrivacyProvider>(
                  create: (_) => PrivacyProvider(initialHidden: false)),
              ChangeNotifierProvider<ServerFeaturesProvider>.value(
                  value: provider),
            ],
            child: MaterialApp(
              theme: dark ? SureTheme.dark : SureTheme.light,
              locale: locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              home: Scaffold(
                body: GoalsScreen(
                    service: service(), auth: auth(), accounts: _accounts),
              ),
            ),
          ));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('goalsSummary')), findsOneWidget);
          expect(tester.takeException(), isNull);
          final tiles = [
            'goalsSummaryVelocity',
            'goalsSummaryNeeds',
            'goalsSummaryOnTrack',
          ].map((k) => tester.getSize(find.byKey(ValueKey(k)))).toList();
          expect(tiles.map((s) => s.width).toSet().length, 1);
          expect(tiles.map((s) => s.height).toSet().length, 1);
        });
      }
    }
  });

  group('goals.lifecycle', () {
    const withLifecycle = {'goals', 'goals.pledges', 'goals.lifecycle'};

    Future<void> openDetail(WidgetTester tester, String name,
        {Set<String> features = withLifecycle}) async {
      await pumpGoals(tester, features: features);
      if (find.text(name).evaluate().isEmpty) {
        await tester.tap(find.text('Paused · 1'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
      expect(find.byType(GoalDetailScreen), findsOneWidget);
    }

    List<String> actionTitles(WidgetTester tester) => [
          for (final row in tester.widgetList<SureListRow>(find.descendant(
              of: find.byKey(const ValueKey('goalActions')),
              matching: find.byType(SureListRow))))
            row.title,
        ];

    testWidgets('shows only available actions, in order, instead of the link',
        (tester) async {
      api.goals['g1']!['available_actions'] = [
        'archive',
        'consume',
        'complete',
        'pause',
      ];
      await openDetail(tester, 'Emergency fund');
      expect(actionTitles(tester),
          ['Spend from this goal', 'Pause', 'Mark complete', 'Archive']);
      expect(find.text('Pause or archive on the web'), findsNothing);
      expect(find.byKey(const ValueKey('goalEdit')), findsOneWidget);
      expect(find.byKey(const ValueKey('goalDelete')), findsOneWidget);
      expect(
          tester.getTopLeft(find.byKey(const ValueKey('goalActions'))).dy,
          lessThan(
              tester.getTopLeft(find.byKey(const ValueKey('goalDelete'))).dy));
    });

    testWidgets('a paused goal offers resume', (tester) async {
      await openDetail(tester, 'Old sofa');
      expect(actionTitles(tester), ['Resume', 'Mark complete', 'Archive']);
    });

    testWidgets('without the feature the web link stays', (tester) async {
      await openDetail(tester, 'Emergency fund',
          features: {'goals', 'goals.pledges'});
      expect(find.byKey(const ValueKey('goalActions')), findsNothing);
      expect(find.text('Pause or archive on the web'), findsOneWidget);
    });

    testWidgets('pauses, replaces the goal and reloads the list',
        (tester) async {
      await openDetail(tester, 'Emergency fund');
      final lists = api.calls.where((c) => c == 'GET /api/v1/goals').length;
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('goalAction-pause')), 200);
      await tester.tap(find.byKey(const ValueKey('goalAction-pause')));
      await tester.pumpAndSettle();

      expect(api.calls, contains('PATCH /api/v1/goals/g1/pause'));
      expect(find.text('Goal paused'), findsOneWidget);
      expect(find.text('Paused · 62%'), findsOneWidget);
      expect(actionTitles(tester), ['Resume', 'Mark complete', 'Archive']);
      expect(api.calls.where((c) => c == 'GET /api/v1/goals').length,
          lists + 1);
    });

    testWidgets('archive and complete ask first', (tester) async {
      await openDetail(tester, 'Emergency fund');
      for (final (action, title) in const [
        ('archive', 'Archive this goal?'),
        ('complete', 'Mark this goal complete?'),
      ]) {
        await tester.scrollUntilVisible(
            find.byKey(ValueKey('goalAction-$action')), 200);
        await tester.tap(find.byKey(ValueKey('goalAction-$action')));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(api.calls, isNot(contains('PATCH /api/v1/goals/g1/$action')));
      }

      await tester.tap(find.byKey(const ValueKey('goalAction-archive')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Archive'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('PATCH /api/v1/goals/g1/archive'));
      expect(find.text('Goal archived'), findsOneWidget);
      expect(actionTitles(tester), ['Unarchive']);
    });

    testWidgets('a 422 invalid_transition shows the server message',
        (tester) async {
      await openDetail(tester, 'Emergency fund');
      api.writeOverride = http.Response(
          jsonEncode({
            'error': 'invalid_transition',
            'message': "Goal can't be paused from its current state.",
            'errors': ["Goal can't be paused from its current state."],
          }),
          422);
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('goalAction-pause')), 200);
      await tester.tap(find.byKey(const ValueKey('goalAction-pause')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
          find.text("Goal can't be paused from its current state."), -200);
      expect(find.text("Goal can't be paused from its current state."),
          findsOneWidget);
      expect(find.text('Goal paused'), findsNothing);
    });

    testWidgets('spends from a single-account goal without a picker',
        (tester) async {
      await openDetail(tester, 'Emergency fund');
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('goalAction-consume')), 200);
      await tester.tap(find.byKey(const ValueKey('goalAction-consume')));
      await tester.pumpAndSettle();
      expect(find.text('Spend from this goal'), findsWidgets);
      expect(find.byKey(const ValueKey('goalConsumeAccount')), findsNothing);

      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey('goalConsumeAmount')),
              matching: find.byType(EditableText)),
          '200');
      await tester.tap(find.byKey(const ValueKey('goalConsumeSave')));
      await tester.pumpAndSettle();

      expect(api.calls, contains('POST /api/v1/goals/g1/consume'));
      expect(api.bodies.last, {
        'consumption': {'amount': '200'},
      });
      expect(find.text('Spend recorded'), findsOneWidget);
      expect(find.byType(GoalConsumeSheet), findsNothing);
    });

    testWidgets('picks the account when several fund the goal',
        (tester) async {
      api.goals['g1']!['linked_accounts'] = [
        linkedJson('acc1'),
        linkedJson('acc2', name: 'Brokerage'),
      ];
      await openDetail(tester, 'Emergency fund');
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('goalAction-consume')), 200);
      await tester.tap(find.byKey(const ValueKey('goalAction-consume')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('goalConsumeAccount')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('goalConsumeAccount')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Brokerage').last);
      await tester.pumpAndSettle();

      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey('goalConsumeAmount')),
              matching: find.byType(EditableText)),
          '50');
      await tester.tap(find.byKey(const ValueKey('goalConsumeSave')));
      await tester.pumpAndSettle();
      expect(api.bodies.last, {
        'consumption': {'amount': '50', 'account_id': 'acc2'},
      });
    });

    testWidgets('a 422 consumption_refused stays in the sheet with its message',
        (tester) async {
      await openDetail(tester, 'Emergency fund');
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('goalAction-consume')), 200);
      await tester.tap(find.byKey(const ValueKey('goalAction-consume')));
      await tester.pumpAndSettle();
      api.writeOverride = http.Response(
          jsonEncode({
            'error': 'consumption_refused',
            'reason': 'exceeds_earmark',
            'message': 'That is more than the goal has earmarked on this account.',
            'errors': [
              'That is more than the goal has earmarked on this account.'
            ],
          }),
          422);
      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey('goalConsumeAmount')),
              matching: find.byType(EditableText)),
          '99999');
      await tester.tap(find.byKey(const ValueKey('goalConsumeSave')));
      await tester.pumpAndSettle();
      expect(find.byType(GoalConsumeSheet), findsOneWidget);
      expect(
          find.text('That is more than the goal has earmarked on this account.'),
          findsOneWidget);
    });

    testWidgets('lays out at 320 px in dark mode without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(960, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      api.goals['g1']!['linked_accounts'] = [
        linkedJson('acc1'),
        linkedJson('acc2', name: 'Brokerage'),
      ];
      final provider = ServerFeaturesProvider()..debugSet(withLifecycle);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<PrivacyProvider>(
              create: (_) => PrivacyProvider(initialHidden: false)),
          ChangeNotifierProvider<ServerFeaturesProvider>.value(value: provider),
        ],
        child: MaterialApp(
          theme: SureTheme.dark,
          locale: const Locale('sv'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: GoalsScreen(
                service: service(), auth: auth(), accounts: _accounts),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Emergency fund'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('goalAction-consume')), 200);
      await tester.tap(find.byKey(const ValueKey('goalAction-consume')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('goalConsumeAccount')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('renders the list and the form in dark mode', (tester) async {
    tester.view.physicalSize = const Size(960, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<PrivacyProvider>(
      create: (_) => PrivacyProvider(initialHidden: false),
      child: MaterialApp(
        theme: SureTheme.dark,
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: GoalsScreen(
              service: service(), auth: auth(), accounts: _accounts),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Emergency fund'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('New goal'));
    await tester.pumpAndSettle();
    expect(find.text('Fund from'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('privacy mode masks the amounts', (tester) async {
    tester.view.physicalSize = const Size(1170, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<PrivacyProvider>(
      create: (_) => PrivacyProvider(initialHidden: true),
      child: MaterialApp(
        theme: SureTheme.light,
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: GoalsScreen(
              service: service(), auth: auth(), accounts: _accounts),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('\$3,100.00 of \$5,000.00'), findsNothing);
    expect(find.text('62%'), findsNothing);
  });
}
