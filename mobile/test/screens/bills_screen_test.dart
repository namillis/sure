import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/screens/bills_screen.dart';
import 'package:sure_mobile/screens/recurring_form_screen.dart';
import 'package:sure_mobile/services/connectivity_service.dart';
import 'package:sure_mobile/services/preferences_service.dart';
import 'package:sure_mobile/services/recurring_transactions_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';

import '../support/home_fixtures.dart';
import '../support/l10n_harness.dart';
import '../support/recurring_fixtures.dart';

Map<String, dynamic> billJson({
  required String id,
  required String name,
  required int amountCents,
  String? next,
  String? last,
  String status = 'active',
  String billType = 'bill',
  String currency = 'USD',
  bool autopay = false,
  String? paymentUrl,
  String? renewsOn,
  String? trialEndsOn,
  List<Map<String, dynamic>> rules = const [],
}) =>
    {
      ...recurringJson(
        id: id,
        name: name,
        amountCents: amountCents,
        currency: currency,
        status: status,
        rules: rules,
      ),
      'next_expected_date': next,
      'last_occurrence_date': last,
      'bill_type': billType,
      'autopay': autopay,
      'payment_url': paymentUrl,
      'renews_on': renewsOn,
      'trial_ends_on': trialEndsOn,
    };

final _month = [
  billJson(
    id: 'electric',
    name: 'Electric',
    amountCents: 12000,
    next: '2026-11-05',
    last: '2026-10-05',
    autopay: true,
  ),
  billJson(
    id: 'stream',
    name: 'StreamCo',
    amountCents: 1549,
    next: '2026-11-20',
    last: '2026-10-20',
    billType: 'subscription',
    trialEndsOn: '2026-11-25',
    paymentUrl: 'https://example.com/pay',
  ),
  billJson(
    id: 'rent',
    name: 'Rent',
    amountCents: 150000,
    next: '2026-12-01',
    last: '2026-11-01',
    paymentUrl: 'javascript:alert(1)',
  ),
  billJson(
    id: 'car',
    name: 'Car loan',
    amountCents: 30000,
    next: '2027-03-02',
    last: '2026-09-02',
    billType: 'installment',
    renewsOn: '2026-10-01', // In the past: no chip.
    rules: [
      {'frequency': 'monthly', 'interval': 6},
    ],
  ),
  billJson(
    id: 'gym',
    name: 'Old gym',
    amountCents: 4999,
    next: '2026-11-15',
    status: 'inactive',
  ),
  billJson(
    id: 'salary',
    name: 'Salary',
    amountCents: -300000,
    next: '2026-11-25',
    billType: 'income',
  ),
];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PreferencesService.resetForTest();
  });

  MockClient server(List<Map<String, dynamic>> items, {int status = 200}) =>
      MockClient((request) async =>
          http.Response(recurringIndexBody(items), status));

  Future<void> pump(
    WidgetTester tester,
    MockClient client, {
    bool offline = false,
  }) =>
      pumpLocalized(
        tester,
        logicalHeight: 1600,
        ChangeNotifierProvider<ConnectivityService>(
          create: (_) => FakeConnectivity(offline: offline),
          child: BillsScreen(
            service: RecurringTransactionsService(client: client),
            accessTokenLoader: () async => 'token',
            onUnauthorized: () async {},
            accounts: const [],
            familyCurrency: 'USD',
            clock: () => DateTime(2026, 11, 10),
          ),
        ),
      );

  String richText(WidgetTester tester, String key) => tester
      .widget<Text>(find.byKey(ValueKey(key)))
      .textSpan!
      .toPlainText();

  testWidgets('summary shows the month, left to pay and paid progress',
      (tester) async {
    await pump(tester, server(_month));

    expect(find.text('November'), findsOneWidget);
    expect(richText(tester, 'billsLeftToPay'), r'$135.49 left to pay');
    expect(find.text(r'$1,500.00 paid of $1,635.49 · 1 of 3 bills'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('billsOtherCurrencies')), findsNothing);
  });

  testWidgets('sections, row sublines and folded Paid and Paused',
      (tester) async {
    await pump(tester, server(_month));

    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('Due this month'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Due Nov 5 · Autopay'), findsOneWidget);
    expect(find.text('Nov 20'), findsOneWidget);
    expect(find.text('Every 6 months · Mar 2, 2027'), findsOneWidget);
    expect(find.text('Salary'), findsNothing);

    // Paid and Paused are folded.
    expect(find.text('Paid this month · 1'), findsOneWidget);
    expect(find.text('Paused · 1'), findsOneWidget);
    expect(find.text('Rent'), findsNothing);
    expect(find.text('Old gym'), findsNothing);

    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('billsHeader-paidThisMonth')),
        matching: find.text('Show')));
    await tester.pumpAndSettle();
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('Paid Nov 1'), findsOneWidget);
    expect(find.text('Hide'), findsOneWidget);

    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('billsHeader-paused')),
        matching: find.text('Show')));
    await tester.pumpAndSettle();
    expect(find.text('Old gym'), findsOneWidget);
    final paused = tester.widget<Opacity>(find
        .ancestor(
            of: find.byKey(const ValueKey('bill-gym')),
            matching: find.byType(Opacity))
        .first);
    expect(paused.opacity, lessThan(1));
  });

  testWidgets('type and trial chips, and Pay only for http(s) links',
      (tester) async {
    await pump(tester, server(_month));
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('billsHeader-paidThisMonth')),
        matching: find.text('Show')));
    await tester.pumpAndSettle();

    expect(find.text('Subscription'), findsOneWidget);
    expect(find.text('Trial ends Nov 25'), findsOneWidget);
    expect(find.text('Installment'), findsOneWidget);
    expect(find.textContaining('Renews'), findsNothing);

    // StreamCo has an https link; Rent's javascript: link is ignored.
    expect(find.byKey(const ValueKey('billPayButton')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('bill-stream')),
            matching: find.byKey(const ValueKey('billPayButton'))),
        findsOneWidget);
    expect(find.text('Pay'), findsOneWidget);
  });

  testWidgets('other currencies stay out of the totals', (tester) async {
    await pump(
      tester,
      server([
        billJson(
            id: 'a', name: 'A', amountCents: 2500, next: '2026-11-25'),
        billJson(
            id: 'b',
            name: 'B',
            amountCents: 9900,
            next: '2026-11-26',
            currency: 'EUR'),
      ]),
    );

    expect(richText(tester, 'billsLeftToPay'), r'$25.00 left to pay');
    expect(find.text('Also 1 bill in other currencies'), findsOneWidget);
    expect(find.text(r'$0.00 paid of $25.00 · 0 of 2 bills'), findsOneWidget);
  });

  testWidgets('no summary when nothing is due, overdue or paid this month',
      (tester) async {
    await pump(
      tester,
      server([
        billJson(
            id: 'a',
            name: 'Insurance',
            amountCents: 2500,
            next: '2027-01-25',
            last: '2026-07-25'),
      ]),
    );

    expect(find.text('Insurance'), findsOneWidget);
    expect(find.byKey(const ValueKey('billsLeftToPay')), findsNothing);
  });

  testWidgets('tapping a row opens the recurring editor', (tester) async {
    await pump(tester, server(_month));

    await tester.tap(find.text('Electric'));
    await tester.pumpAndSettle();
    expect(find.byType(RecurringFormScreen), findsOneWidget);
  });

  testWidgets('empty state offers the web Bills page', (tester) async {
    await pump(tester, server([_month.last])); // Only income.

    expect(find.text('No bills yet'), findsOneWidget);
    expect(
        find.text('Mark a transaction as recurring, or find bills from your '
            'history on the web.'),
        findsOneWidget);
    expect(find.text('Find bills on the web'), findsOneWidget);
  });

  testWidgets('error state retries', (tester) async {
    var calls = 0;
    await pump(
      tester,
      MockClient((request) async {
        calls++;
        return calls == 1
            ? http.Response('{"error":"boom"}', 500)
            : http.Response(recurringIndexBody(_month), 200);
      }),
    );

    expect(find.text("Couldn't load bills"), findsOneWidget);
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();
    expect(find.text('Electric'), findsOneWidget);
  });

  testWidgets('offline with nothing loaded says so', (tester) async {
    await pump(tester, server(const [], status: 500), offline: true);

    expect(find.text("You're offline"), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
  });

  testWidgets('Swedish fits a 320 px wide screen', (tester) async {
    tester.view.physicalSize = const Size(960, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<PrivacyProvider>(
        create: (_) => PrivacyProvider(initialHidden: false),
        child: MaterialApp(
          theme: SureTheme.light,
          locale: const Locale('sv'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: BillsScreen(
              service: RecurringTransactionsService(client: server(_month)),
              accessTokenLoader: () async => 'token',
              onUnauthorized: () async {},
              accounts: const [],
              familyCurrency: 'USD',
              clock: () => DateTime(2026, 11, 10),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final header in ['paidThisMonth', 'paused']) {
      await tester.tap(find.descendant(
          of: find.byKey(ValueKey('billsHeader-$header')),
          matching: find.text('Visa')));
      await tester.pumpAndSettle();
    }

    expect(find.text('Provperiod slutar 25 nov.'), findsOneWidget);
    expect(find.text('Betala'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('billPaymentUri accepts only http and https', () {
    expect(billPaymentUri('https://example.com/pay'), isNotNull);
    expect(billPaymentUri('http://example.com'), isNotNull);
    expect(billPaymentUri('javascript:alert(1)'), isNull);
    expect(billPaymentUri('mailto:a@example.com'), isNull);
    expect(billPaymentUri('example.com'), isNull);
  });
}
