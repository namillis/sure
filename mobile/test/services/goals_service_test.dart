import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/goal.dart';
import 'package:sure_mobile/services/goals_service.dart';

import '../support/goal_fixtures.dart';

void main() {
  late List<http.Request> requests;

  GoalsService service(http.Response Function(http.Request) handler) =>
      GoalsService(
        client: MockClient((request) async {
          requests.add(request);
          return handler(request);
        }),
      );

  setUp(() => requests = []);

  test('lists goals and parses the card fields', () async {
    final result = await service((_) => http.Response(
            jsonEncode({
              'goals': [
                goalJson('g1',
                    callout: 'reaches goal around Mar 2027',
                    pledges: [pledgeJson('p1')]),
                goalJson('g2', state: 'paused'),
              ],
            }),
            200))
        .listGoals(accessToken: 't');

    expect(result['success'], true);
    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/api/v1/goals');
    final goals = result['goals'] as List<Goal>;
    expect(goals.map((g) => g.id), ['g1', 'g2']);
    final g = goals.first;
    expect(g.currentAmount!.formatted, '\$3,100.00');
    expect(g.targetAmount!.cents, 500000);
    expect(g.progressPercent, 62);
    expect(g.targetDate, DateTime(2027, 4, 30));
    expect(g.statusCallout, 'reaches goal around Mar 2027');
    expect(g.openPledges.single.accountName, 'Ally Savings');
    expect(g.linkedAccounts.single.wholeAccount, true);
    expect(goals[1].displayStatus, 'paused');
  });

  test('reports feature_disabled and insufficient_scope codes', () async {
    final disabled = await service((_) => http.Response(
            jsonEncode({
              'error': 'feature_disabled',
              'message': 'Preview features are not enabled for this user',
            }),
            403))
        .listGoals(accessToken: 't');
    expect(disabled['success'], false);
    expect(disabled['code'], 'feature_disabled');

    final scope = await service((_) => http.Response(
            jsonEncode({'error': 'insufficient_scope', 'message': 'nope'}),
            403))
        .deleteGoal(accessToken: 't', id: 'g1');
    expect(scope['code'], 'insufficient_scope');
  });

  test('401 is unauthorized', () async {
    final result = await service((_) => http.Response('{}', 401))
        .getGoal(accessToken: 't', id: 'g1');
    expect(result, {'success': false, 'error': 'unauthorized'});
  });

  test('a 422 surfaces the validation details', () async {
    final result = await service((_) => http.Response(
            jsonEncode({
              'error': 'validation_failed',
              'message': 'Goal could not be created',
              'errors': ['Target amount must be greater than 0'],
            }),
            422))
        .createGoal(
            accessToken: 't', goal: const GoalInput(name: 'x'));
    expect(result['error'], 'Target amount must be greater than 0');
    expect(result['code'], 'validation_failed');
  });

  test('create and update send the goal body', () async {
    final s = service((r) => http.Response(
        jsonEncode(goalJson('g1')), r.method == 'POST' ? 201 : 200));
    const input = GoalInput(
      name: 'Trip',
      targetAmount: '2500.5',
      targetDate: '2027-06-01',
      icon: 'plane',
      kind: 'one_off',
      accountIds: ['acc1', 'acc2'],
      allocations: {'acc1': '300', 'acc2': null},
    );
    final created = await s.createGoal(accessToken: 't', goal: input);
    expect(created['goal'], isA<Goal>());
    expect(requests.last.url.path, '/api/v1/goals');
    expect(jsonDecode(requests.last.body), {
      'goal': {
        'name': 'Trip',
        'target_amount': '2500.5',
        'target_date': '2027-06-01',
        'icon': 'plane',
        'kind': 'one_off',
        'account_ids': ['acc1', 'acc2'],
        'allocations': {'acc1': '300', 'acc2': ''},
      },
    });

    await s.updateGoal(
        accessToken: 't', id: 'g1', goal: const GoalInput(targetDate: ''));
    expect(requests.last.method, 'PATCH');
    expect(requests.last.url.path, '/api/v1/goals/g1');
    expect(jsonDecode(requests.last.body), {
      'goal': {'target_date': ''},
    });
  });

  test('pledge create, renew and cancel', () async {
    final s = service((r) => http.Response(
        jsonEncode({'pledge': pledgeJson('p1'), 'goal': goalJson('g1')}),
        r.method == 'POST' ? 201 : 200));

    final created = await s.createPledge(
        accessToken: 't', goalId: 'g1', amount: '150', accountId: 'acc1');
    expect(created['goal'], isA<Goal>());
    expect((created['pledge'] as GoalPledge).id, 'p1');
    expect(requests.last.url.path, '/api/v1/goals/g1/pledges');
    expect(jsonDecode(requests.last.body), {
      'pledge': {'amount': '150', 'account_id': 'acc1'},
    });

    await s.renewPledge(accessToken: 't', goalId: 'g1', pledgeId: 'p1');
    expect(requests.last.method, 'PATCH');
    expect(requests.last.url.path, '/api/v1/goals/g1/pledges/p1/renew');

    await s.cancelPledge(accessToken: 't', goalId: 'g1', pledgeId: 'p1');
    expect(requests.last.method, 'DELETE');
    expect(requests.last.url.path, '/api/v1/goals/g1/pledges/p1');
  });

  test('delete accepts the 200 message body', () async {
    final result = await service((_) => http.Response(
            jsonEncode({'message': 'Goal deleted successfully'}), 200))
        .deleteGoal(accessToken: 't', id: 'g1');
    expect(result['success'], true);
    expect(requests.single.method, 'DELETE');
  });

  test('loads the summary', () async {
    final result = await service(
            (_) => http.Response(jsonEncode(goalsSummaryJson()), 200))
        .getSummary(accessToken: 't');
    expect(requests.single.url.path, '/api/v1/goals/summary');
    final s = result['summary'] as GoalsSummary;
    expect(s.velocity30d!.formatted, '\$420.00');
    expect(s.velocityPrior30d!.cents, 31000);
    expect(s.needsThisMonth!.formatted, '\$780.00');
    expect([s.onTrackCount, s.trackedTotal, s.reachedCount, s.behindCount],
        [1, 2, 0, 1]);
    expect(s.saved!.formatted, '\$10,000.00');
    expect(s.target!.formatted, '\$23,000.00');
  });

  test('transitions and consumes, parsing available_actions', () async {
    final s = service((_) =>
        http.Response(jsonEncode(goalJson('g1', state: 'paused')), 200));
    final paused =
        await s.transitionGoal(accessToken: 't', id: 'g1', action: 'pause');
    expect(requests.last.method, 'PATCH');
    expect(requests.last.url.path, '/api/v1/goals/g1/pause');
    expect(requests.last.body, isEmpty);
    expect((paused['goal'] as Goal).availableActions,
        ['resume', 'complete', 'archive']);

    await s.consumeGoal(accessToken: 't', id: 'g1', amount: '200');
    expect(requests.last.method, 'POST');
    expect(requests.last.url.path, '/api/v1/goals/g1/consume');
    expect(jsonDecode(requests.last.body), {
      'consumption': {'amount': '200'},
    });
    await s.consumeGoal(
        accessToken: 't', id: 'g1', amount: '5', accountId: 'acc2');
    expect(jsonDecode(requests.last.body), {
      'consumption': {'amount': '5', 'account_id': 'acc2'},
    });
  });

  test('a refused transition or spend surfaces the server message', () async {
    final result = await service((_) => http.Response(
            jsonEncode({
              'error': 'consumption_refused',
              'reason': 'not_active',
              'message': 'This goal is no longer active.',
              'errors': ['This goal is no longer active.'],
            }),
            422))
        .consumeGoal(accessToken: 't', id: 'g1', amount: '1');
    expect(result['success'], false);
    expect(result['code'], 'consumption_refused');
    expect(result['error'], 'This goal is no longer active.');
  });
}
