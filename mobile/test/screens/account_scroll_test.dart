import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/models/account.dart';
import 'package:sure_mobile/models/category.dart' as models;
import 'package:sure_mobile/models/offline_transaction.dart';
import 'package:sure_mobile/providers/auth_provider.dart';
import 'package:sure_mobile/providers/categories_provider.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/providers/transactions_provider.dart';
import 'package:sure_mobile/screens/transactions_list_screen.dart';
import 'package:sure_mobile/services/account_detail_service.dart';
import 'package:sure_mobile/services/preferences_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/account_detail_header.dart';
import 'package:sure_mobile/widgets/balance_history_chart.dart';
import 'package:sure_mobile/widgets/trades_list.dart';

class _FakeAuthProvider extends AuthProvider {
  @override
  Future<String?> getValidAccessToken() async => 'token';

  @override
  Future<void> logout() async {}
}

class _FakeTransactionsProvider extends TransactionsProvider {
  _FakeTransactionsProvider(this._items);

  final List<OfflineTransaction> _items;
  int fetches = 0;

  @override
  List<OfflineTransaction> get offlineTransactions => _items;

  @override
  bool get isLoading => false;

  @override
  String? get error => null;

  @override
  Future<void> fetchTransactions({
    required String accessToken,
    String? accountId,
    bool forceSync = false,
  }) async {
    fetches++;
  }
}

class _FakeCategoriesProvider extends CategoriesProvider {
  @override
  List<models.Category> get categories => const [];

  @override
  bool get isLoading => false;

  @override
  Future<void> fetchCategories({required String accessToken}) async {}
}

Account _account(String type) => Account(
      id: 'acct_1',
      name: 'Account',
      balance: r'$1,000.00',
      currency: 'USD',
      classification: 'asset',
      accountType: type,
    );

List<OfflineTransaction> _transactions(int count) => [
      for (var i = 0; i < count; i++)
        OfflineTransaction(
          id: 'txn_$i',
          localId: 'local_$i',
          accountId: 'acct_1',
          name: 'Txn $i',
          date: '2026-11-01',
          amount: r'$10.00',
          currency: 'USD',
          nature: 'expense',
          syncStatus: SyncStatus.synced,
        ),
    ];

Widget _app(Widget home, {TransactionsProvider? transactions}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
            create: (_) => _FakeAuthProvider()),
        ChangeNotifierProvider<PrivacyProvider>(
          create: (_) => PrivacyProvider(initialHidden: false),
        ),
        ChangeNotifierProvider<TransactionsProvider>(
          create: (_) => transactions ?? _FakeTransactionsProvider(const []),
        ),
        ChangeNotifierProvider<CategoriesProvider>(
          create: (_) => _FakeCategoriesProvider(),
        ),
      ],
      child: MaterialApp(
        theme: SureTheme.light,
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      ),
    );

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

AccountDetailService _chartService() => AccountDetailService(
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/balances') {
          return http.Response(
            jsonEncode({
              'balances': [
                for (var day = 1; day <= 20; day++)
                  {
                    'id': 'bal_$day',
                    'date': '2026-10-${day.toString().padLeft(2, '0')}',
                    'currency': 'USD',
                    'balance': '\$${day * 10}.00',
                    'balance_cents': day * 1000,
                  },
              ],
              'pagination': {
                'page': 1,
                'per_page': 100,
                'total_count': 20,
                'total_pages': 1
              },
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PreferencesService.resetForTest();
  });

  testWidgets('bank account: header scrolls away with the transactions',
      (tester) async {
    _phone(tester);
    final provider = _FakeTransactionsProvider(_transactions(40));
    await tester.pumpWidget(_app(
      TransactionsListScreen(account: _account('depository')),
      transactions: provider,
    ));
    await tester.pumpAndSettle();

    final appBarBottom = tester.getBottomLeft(find.byKey(const ValueKey('accountNavBar'))).dy;
    final headerTop = tester.getTopLeft(find.byType(AccountDetailHeader)).dy;
    expect(headerTop, greaterThanOrEqualTo(appBarBottom));
    expect(find.byKey(const ValueKey('accountSectionSwitcher')), findsNothing);

    await tester.drag(find.text('Txn 0'), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byType(AccountDetailHeader)).dy,
      lessThan(headerTop - 100),
    );

    await tester.fling(find.text('Txn 3'), const Offset(0, -1500), 3000);
    await tester.pumpAndSettle();
    expect(find.byType(AccountDetailHeader).hitTestable(), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    // Pulling back down brings the header back, and a pull past the top
    // refreshes.
    final fetchesBefore = provider.fetches;
    for (var i = 0; i < 4; i++) {
      await tester.fling(
          find.byType(CustomScrollView).last, const Offset(0, 1500), 3000);
      await tester.pumpAndSettle();
    }
    expect(find.byType(AccountDetailHeader).hitTestable(), findsOneWidget);
    await tester.fling(find.text('Txn 0'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(provider.fetches, greaterThan(fetchesBefore));
  });

  testWidgets('investment account: switcher stays pinned under the app bar',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(
      TransactionsListScreen(account: _account('investment')),
      transactions: _FakeTransactionsProvider(_transactions(40)),
    ));
    await tester.pumpAndSettle();

    final switcher = find.byKey(const ValueKey('accountSectionSwitcher'));
    final appBarBottom = tester.getBottomLeft(find.byKey(const ValueKey('accountNavBar'))).dy;
    final startTop = tester.getTopLeft(switcher).dy;
    expect(startTop, greaterThan(appBarBottom + 100));

    await tester.tap(find.text('Transactions'));
    await tester.pumpAndSettle();
    await tester.fling(find.text('Txn 0'), const Offset(0, -2000), 3000);
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(switcher).dy, moreOrLessEquals(appBarBottom));
    expect(find.byType(AccountDetailHeader).hitTestable(), findsNothing);
    expect(find.text('Txn 0').hitTestable(), findsNothing);
  });

  testWidgets('chart drag selects a point instead of scrolling the header',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(
      Scaffold(
        appBar: AppBar(title: const Text('Account')),
        body: NestedScrollView(
          headerSliverBuilder: (_, __) => [
            SliverToBoxAdapter(
              child: AccountDetailHeader(
                account: _account('depository'),
                accountDetailService: _chartService(),
              ),
            ),
          ],
          body: ListView(
            children: [
              for (var i = 0; i < 40; i++) ListTile(title: Text('Row $i')),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final chart = find.byType(BalanceHistoryChart);
    expect(chart, findsOneWidget);
    final headerTop = tester.getTopLeft(find.byType(AccountDetailHeader)).dy;

    // A horizontal drag scrubs the chart; the selected date replaces the
    // change line while the finger is down.
    final gesture = await tester.startGesture(tester.getCenter(chart));
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(const Offset(40, 4));
    await tester.pump();
    expect(find.textContaining('Oct'), findsOneWidget);
    await gesture.moveBy(const Offset(-60, -6));
    await tester.pump();
    expect(tester.getTopLeft(find.byType(AccountDetailHeader)).dy, headerTop);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.textContaining('Oct'), findsNothing);

    // Press-and-hold then drag also scrubs, even with vertical drift.
    final hold = await tester.startGesture(tester.getCenter(chart));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await hold.moveBy(const Offset(30, -30));
    await tester.pump();
    expect(find.textContaining('Oct'), findsOneWidget);
    expect(tester.getTopLeft(find.byType(AccountDetailHeader)).dy, headerTop);
    await hold.up();
    await tester.pumpAndSettle();

    // A vertical drag on the chart scrolls the page.
    await tester.drag(chart, const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byType(AccountDetailHeader)).dy,
      lessThan(headerTop - 40),
    );
  });

  testWidgets('activity still pages inside a NestedScrollView', (tester) async {
    _phone(tester);
    final pages = <String>[];
    final service = AccountDetailService(
      client: MockClient((request) async {
        final page = request.url.queryParameters['page']!;
        pages.add(page);
        final start = (int.parse(page) - 1) * 25;
        return http.Response(
          jsonEncode({
            'trades': [
              for (var i = start; i < start + 25; i++)
                {
                  'id': 'trade_$i',
                  'date': '2026-10-01',
                  'name': 'Trade $i',
                  'amount': r'$1.00',
                  'currency': 'USD',
                  'qty': '1',
                  'price': r'$1.00',
                },
            ],
            'pagination': {
              'page': int.parse(page),
              'per_page': 25,
              'total_count': 75,
              'total_pages': 3
            },
          }),
          200,
        );
      }),
    );

    await tester.pumpWidget(_app(
      Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (_, __) => [
            const SliverToBoxAdapter(child: SizedBox(height: 300)),
          ],
          body: TradesList(
            account: _account('investment'),
            accountDetailService: service,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(pages, ['1']);

    await tester.fling(find.byType(ListView), const Offset(0, -4000), 4000);
    await tester.pumpAndSettle();
    expect(pages, containsAllInOrder(['1', '2']));
  });
}
