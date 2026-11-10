import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sure_mobile/models/account.dart';
import 'package:sure_mobile/screens/recurring_screen.dart';
import 'package:sure_mobile/services/preferences_service.dart';
import 'package:sure_mobile/services/recurring_transactions_service.dart';
import 'package:sure_mobile/widgets/sure_text_field.dart';

import '../support/l10n_harness.dart';
import '../support/recurring_fixtures.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PreferencesService.resetForTest();
  });

  final accounts = [
    Account.fromJson({
      'id': 'acct_1',
      'name': 'Checking',
      'balance': r'$1,000.00',
      'currency': 'USD',
      'classification': 'asset',
      'account_type': 'depository',
    }),
  ];

  /// A fake server over [items]; records every non-GET request.
  MockClient server(
    List<Map<String, dynamic>> items, {
    List<http.Request>? writes,
    int listStatus = 200,
  }) =>
      MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(recurringIndexBody(items), listStatus);
        }
        writes?.add(request);
        if (request.method == 'POST') {
          return http.Response(jsonEncode(recurringJson(id: 'new')), 201);
        }
        if (request.method == 'DELETE') {
          return http.Response('{"message":"ok"}', 200);
        }
        return http.Response(jsonEncode(recurringJson()), 200);
      });

  /// The text field under the SureTextField labelled [label].
  Finder field(String label) => find.descendant(
        of: find.ancestor(
            of: find.text(label), matching: find.byType(SureTextField)),
        matching: find.byType(TextFormField),
      );

  // Tall enough that the whole form is built without scrolling.
  Future<void> pump(WidgetTester tester, MockClient client) => pumpLocalized(
        tester,
        logicalHeight: 1600,
        RecurringScreen(
          service: RecurringTransactionsService(client: client),
          accessTokenLoader: () async => 'token',
          onUnauthorized: () async {},
          accounts: accounts,
          clock: () => DateTime(2026, 11, 10),
        ),
      );

  testWidgets('lists items by section with totals and row details',
      (tester) async {
    await pump(
      tester,
      server([
        recurringJson(),
        recurringJson(
          id: 'rt_2',
          name: 'Salary',
          amountCents: -300000,
          amount: r'-$3,000.00',
          nextDate: '2026-12-25',
          rules: [
            {'frequency': 'monthly', 'interval': 1},
          ],
        ),
        recurringJson(id: 'rt_3', name: 'Old gym', status: 'inactive'),
      ]),
    );

    expect(find.text('UPCOMING THIS MONTH'), findsOneWidget);
    expect(find.text('LATER'), findsOneWidget);
    expect(find.text('INACTIVE'), findsOneWidget);
    expect(find.text('Gym Membership'), findsOneWidget);
    expect(find.text('Monthly on day 20 · Next Nov 20 · Checking'),
        findsOneWidget);
    expect(find.text('+\$3,000.00'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
    expect(find.textContaining('Inactive', findRichText: true), findsWidgets);
    expect(find.text('Monthly out'), findsOneWidget);
    expect(find.text(r'$49.99'), findsNWidgets(3)); // two rows + out total
    expect(find.text(r'$3,000.00'), findsOneWidget); // in total
  });

  testWidgets('shows the empty state', (tester) async {
    await pump(tester, server([]));
    expect(find.text('No recurring transactions yet'), findsOneWidget);
  });

  testWidgets('shows the error state with retry', (tester) async {
    await pump(tester, server([], listStatus: 500));
    expect(find.text("Couldn't load recurring transactions"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('add form validates required fields, then creates',
      (tester) async {
    final writes = <http.Request>[];
    await pump(tester, server([], writes: writes));

    await tester.tap(find.text('Add recurring'));
    await tester.pumpAndSettle();
    expect(find.text('New recurring'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name'), findsOneWidget);
    expect(find.text('Enter an amount greater than zero'), findsOneWidget);
    expect(writes, isEmpty);

    await tester.enterText(
        field('Name'), 'Gym Membership');
    await tester.enterText(
        field('Amount'), '49.99');
    await tester.enterText(
        field('Payment link'), 'ftp://x');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a link starting with http:// or https://'),
        findsOneWidget);
    expect(writes, isEmpty);

    await tester.enterText(
        field('Payment link'), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(writes, hasLength(1));
    expect(writes.single.url.path, '/api/v1/recurring_transactions');
    final attrs = (jsonDecode(writes.single.body)
        as Map<String, dynamic>)['recurring_transaction'] as Map;
    expect(attrs['name'], 'Gym Membership');
    expect(attrs['amount'], 49.99);
    expect(attrs['currency'], 'USD');
    expect(attrs['status'], 'active');
    expect(attrs['next_expected_date'], '2026-11-10');
    expect(attrs['last_occurrence_date'], '2026-10-10');
    expect(attrs['expected_day_of_month'], 10);
    expect(attrs.containsKey('account_id'), false);
    // Back on the list.
    expect(find.text('New recurring'), findsNothing);
  });

  testWidgets('income is sent as a negative amount', (tester) async {
    final writes = <http.Request>[];
    await pump(tester, server([], writes: writes));
    await tester.tap(find.text('Add recurring'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Income'));
    await tester.enterText(field('Name'), 'Pay');
    await tester.enterText(
        field('Amount'), '3000');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final attrs = (jsonDecode(writes.single.body)
        as Map<String, dynamic>)['recurring_transaction'] as Map;
    expect(attrs['amount'], -3000);
  });

  testWidgets('edit sends only the fields the API updates', (tester) async {
    final writes = <http.Request>[];
    await pump(tester, server([recurringJson()], writes: writes));

    await tester.tap(find.text('Gym Membership'));
    await tester.pumpAndSettle();
    expect(find.text('Edit recurring'), findsOneWidget);

    await tester.enterText(
        field('Notes'), 'Cancel in March');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(writes.single.method, 'PATCH');
    expect(writes.single.url.path, '/api/v1/recurring_transactions/rt_1');
    final attrs = (jsonDecode(writes.single.body)
        as Map<String, dynamic>)['recurring_transaction'] as Map;
    expect(attrs.keys.toSet(), {
      'status',
      'next_expected_date',
      'expected_day_of_month',
      'autopay',
      'payment_url',
      'notes',
    });
    expect(attrs['notes'], 'Cancel in March');
  });

  testWidgets('pause from the row menu sets status inactive', (tester) async {
    final writes = <http.Request>[];
    await pump(tester, server([recurringJson()], writes: writes));

    await tester.tap(find.byTooltip('More actions for Gym Membership'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();

    expect(jsonDecode(writes.single.body), {
      'recurring_transaction': {'status': 'inactive'},
    });
    expect(find.text('Gym Membership paused'), findsOneWidget);
  });

  testWidgets('delete asks first and only deletes on confirm',
      (tester) async {
    final writes = <http.Request>[];
    await pump(tester, server([recurringJson()], writes: writes));

    await tester.tap(find.byTooltip('More actions for Gym Membership'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Gym Membership?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);

    await tester.tap(find.byTooltip('More actions for Gym Membership'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Delete')));
    await tester.pumpAndSettle();

    expect(writes.single.method, 'DELETE');
    expect(find.text('Recurring item deleted'), findsOneWidget);
  });
}
