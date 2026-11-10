import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/models/recurring_transaction.dart';
import 'package:sure_mobile/utils/recurring_grouping.dart';

import '../support/recurring_fixtures.dart';

RecurringTransaction rt(Map<String, dynamic> json) =>
    RecurringTransaction.fromJson(json);

void main() {
  final today = DateTime(2026, 11, 10);

  test('groups by status and whether it is due this month', () {
    final groups = RecurringGrouping.group([
      rt(recurringJson(id: 'later', nextDate: '2026-12-01')),
      rt(recurringJson(id: 'soon', nextDate: '2026-11-30')),
      rt(recurringJson(id: 'overdue', nextDate: '2026-11-02')),
      rt(recurringJson(id: 'sugg', status: 'suggested')),
      rt(recurringJson(id: 'paused', status: 'paused')),
      rt(recurringJson(id: 'ended', status: 'ended')),
    ], today);

    List<String> ids(RecurringGroup g) => groups[g]!.map((i) => i.id).toList();
    expect(ids(RecurringGroup.upcoming), ['overdue', 'soon']);
    expect(ids(RecurringGroup.later), ['later']);
    expect(ids(RecurringGroup.suggested), ['sugg']);
    expect(ids(RecurringGroup.inactive), ['paused', 'ended']);
  });

  test('monthly totals scale by cadence and skip inactive items', () {
    final totals = RecurringGrouping.monthlyTotals([
      rt(recurringJson(amountCents: 1000)), // monthly, no rules
      rt(recurringJson(amountCents: 1200, rules: [
        {'frequency': 'weekly', 'interval': 1},
      ])),
      rt(recurringJson(amountCents: 12000, rules: [
        {'frequency': 'yearly', 'interval': 1},
      ])),
      rt(recurringJson(amountCents: -300000)), // salary
      rt(recurringJson(amountCents: 99999, status: 'inactive')),
      rt(recurringJson(amountCents: 500, currency: 'SEK')),
    ]);

    expect(totals['USD']!.outflow, closeTo(10 + 12 * 52 / 12 + 10, 1e-9));
    expect(totals['USD']!.inflow, closeTo(3000, 1e-9));
    expect(totals['SEK']!.outflow, closeTo(5, 1e-9));
  });
}
