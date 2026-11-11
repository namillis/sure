import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/models/account.dart';
import 'package:sure_mobile/providers/accounts_provider.dart';
import 'package:sure_mobile/providers/auth_provider.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/screens/account_group_screen.dart';
import 'package:sure_mobile/screens/dashboard_screen.dart';
import 'package:sure_mobile/services/account_detail_service.dart';
import 'package:sure_mobile/services/connectivity_service.dart';
import 'package:sure_mobile/services/family_sync_service.dart';
import 'package:sure_mobile/services/insights_service.dart';
import 'package:sure_mobile/services/net_worth_history_service.dart';
import 'package:sure_mobile/services/preferences_service.dart';
import 'package:sure_mobile/services/spending_vs_normal_service.dart';
import 'package:sure_mobile/services/transaction_search_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';

import '../support/home_fixtures.dart';
import '../support/recurring_fixtures.dart';

final _now = DateTime(2026, 11, 11, 12);

final _accounts = [
  homeAccount('chk', name: 'Checking', balance: r'$1,500.00', cents: 150000),
  homeAccount('sav', name: 'Old savings', balance: r'$0.00', cents: 0),
  homeAccount('uk',
      name: 'UK current',
      currency: 'GBP',
      balance: '£28,708.00',
      cents: 2870800),
  homeAccount('card',
      name: 'Sapphire',
      type: 'credit_card',
      classification: 'liability',
      balance: r'$200.00',
      cents: 20000),
  homeAccount('brk',
      name: 'Brokerage',
      type: 'investment',
      balance: r'$10,000.00',
      cents: 1000000),
];

Map<String, dynamic> _tx(String id, String name) => {
      'id': id,
      'date': '2026-11-10',
      'amount': r'$12.50',
      'currency': 'USD',
      'name': name,
      'classification': 'expense',
      'split_parent': false,
      'account': {
        'id': 'chk',
        'name': 'Checking',
        'account_type': 'depository',
      },
      'category': {'id': 'c1', 'name': 'Coffee', 'color': '#e99537'},
      'merchant': null,
      'tags': [],
      'transfer': null,
    };

String _balances(List<List<Object>> rows) => jsonEncode({
      'balances': [
        for (final r in rows)
          {
            'id': '${r[0]}',
            'date': r[0],
            'currency': 'USD',
            'balance': '${r[1]}',
            'balance_cents': r[1],
          },
      ],
      'pagination': {'page': 1, 'per_page': 100, 'total_count': 1, 'total_pages': 1},
    });

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PreferencesService.resetForTest();
  });

  final balanceRequests = <Uri>[];
  final transactionRequests = <Uri>[];
  setUp(() {
    balanceRequests.clear();
    transactionRequests.clear();
  });

  MockClient client() => MockClient((request) async {
        final path = request.url.path;
        if (path == '/api/v1/balances') {
          balanceRequests.add(request.url);
          switch (request.url.queryParameters['account_id']) {
            case 'chk':
              return http.Response(
                  _balances([
                    ['2026-08-13', 100000],
                    ['2026-11-11', 150000],
                  ]),
                  200);
            case 'card':
              return http.Response(
                  _balances([
                    ['2026-08-13', 20000],
                  ]),
                  200);
            case 'brk':
              return http.Response(
                  _balances([
                    ['2026-08-13', 1000000],
                  ]),
                  200);
            default:
              return http.Response(_balances([]), 200);
          }
        }
        if (path == '/api/v1/transactions') {
          transactionRequests.add(request.url);
          return http.Response(
            jsonEncode({
              'transactions': [
                _tx('t1', 'Blue Bottle'),
                _tx('t2', 'Grocer'),
                _tx('t3', 'Bakery'),
              ],
              'pagination': {
                'page': 1,
                'per_page': 3,
                'total_count': 3,
                'total_pages': 1,
              },
            }),
            200,
          );
        }
        if (path == '/api/v1/insights') {
          return http.Response(
            jsonEncode({
              'insights': [
                {
                  'id': 'i1',
                  'type': 'spending_spike',
                  'title': 'Dining is up 40%',
                  'body': 'Body',
                  'priority': 'high',
                  'status': 'active',
                  'generated_at': '2026-11-09T08:00:00Z',
                },
              ],
            }),
            200,
          );
        }
        if (path == '/api/v1/spending_vs_normal') {
          return http.Response(jsonEncode(spendingJson()), 200);
        }
        if (path == '/api/v1/syncs/latest') {
          return http.Response(
            jsonEncode({
              'data': {
                'id': 's1',
                'status': 'completed',
                'created_at': DateTime(2026, 11, 11, 3).toUtc().toIso8601String(),
                'completed_at':
                    DateTime(2026, 11, 11, 3).toUtc().toIso8601String(),
              },
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      });

  Future<void> pump(
    WidgetTester tester, {
    List<Account>? accounts,
    bool offline = false,
    bool hidden = false,
    DateTime? updatedAt,
    bool cached = false,
    VoidCallback? onOpenActivity,
    Brightness brightness = Brightness.light,
    double width = 390,
  }) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final http = client();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PrivacyProvider>(
              create: (_) => PrivacyProvider(initialHidden: hidden)),
          ChangeNotifierProvider<AccountsProvider>(
            create: (_) => FakeAccountsProvider(
              accounts: accounts ?? _accounts,
              netWorth: r'$11,300.00',
              updatedAt: updatedAt,
              cached: cached,
            ),
          ),
          ChangeNotifierProvider<ConnectivityService>(
              create: (_) => FakeConnectivity(offline: offline)),
          ChangeNotifierProvider<AuthProvider>(create: (_) => FakeAuth()),
        ],
        child: MaterialApp(
          theme:
              brightness == Brightness.dark ? SureTheme.dark : SureTheme.light,
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: DashboardScreen(
            onOpenActivity: onOpenActivity,
            accessTokenLoader: () async => 'token',
            netWorthService: NetWorthHistoryService(
                accountDetailService: AccountDetailService(client: http)),
            searchService: TransactionSearchService(client: http),
            insightsService: InsightsService(client: http),
            spendingService: SpendingVsNormalService(client: http),
            syncService: FamilySyncService(client: http),
            clock: () => _now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the header, net worth trend, rows, Recent and groups',
      (tester) async {
    var openedActivity = 0;
    await pump(tester, onOpenActivity: () => openedActivity++);

    expect(find.text('Home'), findsWidgets);
    expect(find.text('9h'), findsOneWidget, reason: 'sync pill');
    expect(find.bySemanticsLabel('Hide amounts'), findsOneWidget);

    expect(find.text('Net worth'), findsOneWidget);
    expect(find.text(r'$11,300.00'), findsOneWidget);
    final change = tester.widget<Text>(find.byKey(const ValueKey('netWorthChange')));
    expect(change.textSpan!.toPlainText(), r'+$500.00 (4.6%)  3M');
    expect(find.byKey(const ValueKey('netWorthSparkline')), findsOneWidget);
    for (final label in ['1M', '3M', '1Y', 'All']) {
      expect(find.widgetWithText(SureChip, label), findsOneWidget);
    }
    expect(
      balanceRequests.map((u) => u.queryParameters['start_date']).toSet(),
      {'2026-08-13'},
    );
    expect(
      balanceRequests.map((u) => u.queryParameters['account_id']).toSet(),
      {'chk', 'sav', 'card', 'brk'},
      reason: 'GBP accounts are not fetched',
    );

    expect(find.text('Dining is up 40%'), findsOneWidget);
    expect(find.text('Spending 20% above normal'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);

    expect(find.text('Recent'), findsOneWidget);
    expect(transactionRequests.single.queryParameters['per_page'], '3');
    expect(
        transactionRequests.single.queryParameters.containsKey('start_date'),
        isFalse);
    expect(find.byType(SureTransactionRow), findsNWidgets(3));
    await tester.tap(find.text('See all'));
    expect(openedActivity, 1);

    expect(find.text('Accounts'), findsOneWidget);
    final cash = find.byKey(const ValueKey('group-depository'));
    expect(
      tester
          .widget<Text>(find.descendant(of: cash, matching: find.byType(Text)).first)
          .textSpan!
          .toPlainText(),
      'Cash · 3',
    );
    expect(find.descendant(of: cash, matching: find.text(r'$1,500.00')),
        findsOneWidget);
    expect(find.descendant(of: cash, matching: find.text('+ £28,708.00')),
        findsOneWidget);
    expect(find.text(r'-$200.00'), findsOneWidget);
    expect(find.text(r'$10,000.00'), findsOneWidget);

    // Assets first, in the web's order, then liabilities.
    final y = [
      'group-depository',
      'group-investment',
      'group-credit_card',
    ].map((k) => tester.getTopLeft(find.byKey(ValueKey(k))).dy).toList();
    expect(y, orderedEquals([...y]..sort()));
  });

  testWidgets('a range chip reloads the history for that range',
      (tester) async {
    await pump(tester);
    balanceRequests.clear();

    await tester.tap(find.widgetWithText(SureChip, '1M'));
    await tester.pumpAndSettle();

    expect(
      balanceRequests.map((u) => u.queryParameters['start_date']).toSet(),
      {'2026-10-12'},
    );
    final change = tester.widget<Text>(find.byKey(const ValueKey('netWorthChange')));
    expect(change.textSpan!.toPlainText(), endsWith('1M'));

    // Back to a loaded range: no new requests.
    balanceRequests.clear();
    await tester.tap(find.widgetWithText(SureChip, '3M'));
    await tester.pumpAndSettle();
    expect(balanceRequests, isEmpty);

    await tester.tap(find.widgetWithText(SureChip, 'All'));
    await tester.pumpAndSettle();
    expect(balanceRequests, isNotEmpty);
    expect(
        balanceRequests.every((u) => !u.queryParameters.containsKey('start_date')),
        isTrue);
  });

  testWidgets('an account group opens its list with empty accounts collapsed',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('group-depository')));
    await tester.pumpAndSettle();

    expect(find.byType(AccountGroupScreen), findsOneWidget);
    expect(find.text('Cash'), findsWidgets);
    expect(find.text('Checking'), findsOneWidget);
    expect(find.text('UK current'), findsOneWidget);
    expect(find.text('Old savings'), findsNothing);
    expect(find.text('1 empty account · Show'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('emptyAccountsToggle')));
    await tester.pumpAndSettle();
    expect(find.text('Old savings'), findsOneWidget);
    expect(find.text('1 empty account · Hide'), findsOneWidget);
  });

  testWidgets('first run shows one empty state panel and no cards',
      (tester) async {
    await pump(tester, accounts: const []);

    expect(find.byKey(const ValueKey('homeFirstRun')), findsOneWidget);
    expect(find.text('No accounts yet'), findsOneWidget);
    expect(
        find.text(
            'Connect a bank on the web, or add a manual account like a house or car.'),
        findsOneWidget);
    expect(find.text('Connect on the web'), findsOneWidget);
    expect(find.text('Add a manual account'), findsOneWidget);
    expect(find.text('Net worth'), findsNothing);
    expect(find.text('Recent'), findsNothing);
    expect(find.text('Accounts'), findsNothing);
  });

  testWidgets('offline with cached data shows the banner and updated time',
      (tester) async {
    await pump(
      tester,
      offline: true,
      cached: true,
      updatedAt: _now.subtract(const Duration(hours: 2)),
    );

    expect(find.text('Offline · showing data from 2h ago'), findsOneWidget);
    expect(find.text('Updated 2 hours ago'), findsOneWidget);
    expect(find.text(r'$11,300.00'), findsOneWidget);
    expect(balanceRequests, isEmpty, reason: 'history needs the network');
    expect(find.widgetWithText(SureChip, '3M'), findsNothing);
  });

  testWidgets('privacy mode masks the hero, group totals and Recent',
      (tester) async {
    await pump(tester, hidden: true);
    expect(find.text(r'$11,300.00'), findsNothing);
    expect(find.text(r'$••••'), findsWidgets);
    expect(find.text(r'-$12.50'), findsNothing);
    expect(find.text(r'-$••••'), findsWidgets);
    expect(find.bySemanticsLabel('Show amounts'), findsOneWidget);
  });

  for (final brightness in brightnesses) {
    testWidgets('fits a 320 px screen (${brightness.name})', (tester) async {
      await pump(tester, width: 320, brightness: brightness);
      expect(tester.takeException(), isNull);
      expect(find.text('Dining is up 40%'), findsOneWidget);
    });
  }
}

const brightnesses = [Brightness.light, Brightness.dark];
