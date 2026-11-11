import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/l10n/app_localizations_en.dart';
import 'package:sure_mobile/models/account.dart';
import 'package:sure_mobile/models/account_holding.dart';
import 'package:sure_mobile/models/category.dart' as models;
import 'package:sure_mobile/models/offline_transaction.dart';
import 'package:sure_mobile/providers/auth_provider.dart';
import 'package:sure_mobile/providers/categories_provider.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/providers/transactions_provider.dart';
import 'package:sure_mobile/screens/transactions_list_screen.dart';
import 'package:sure_mobile/services/account_detail_service.dart';
import 'package:sure_mobile/services/connectivity_service.dart';
import 'package:sure_mobile/services/transaction_search_service.dart';
import 'package:sure_mobile/services/preferences_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/account_detail_header.dart';
import 'package:sure_mobile/widgets/balance_history_chart.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';
import 'package:sure_mobile/widgets/holdings_list.dart';
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
  }) async =>
      fetches++;
}

class _Connectivity extends ChangeNotifier implements ConnectivityService {
  @override
  bool get isOnline => true;
  @override
  bool get isOffline => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCategoriesProvider extends CategoriesProvider {
  _FakeCategoriesProvider(this._items);

  final List<models.Category> _items;

  @override
  List<models.Category> get categories => _items;

  @override
  bool get isLoading => false;

  @override
  Future<void> fetchCategories({required String accessToken}) async {}
}

Account _account(String type, {String? subtype, DateTime? updatedAt}) =>
    Account(
      id: 'acct_1',
      name: 'Everyday Checking',
      balance: r'$1,000.00',
      currency: 'USD',
      classification: 'asset',
      accountType: type,
      subtype: subtype,
      updatedAt: updatedAt,
    );

OfflineTransaction _txn(String id, String date, String amount,
        {String? categoryId, String? categoryName}) =>
    OfflineTransaction(
      id: id,
      localId: 'local_$id',
      accountId: 'acct_1',
      name: 'Txn $id',
      date: date,
      amount: amount,
      currency: 'USD',
      nature: 'expense',
      categoryId: categoryId,
      categoryName: categoryName,
      syncStatus: SyncStatus.synced,
    );

Widget _app(
  Widget home, {
  List<OfflineTransaction> transactions = const [],
  List<models.Category> categories = const [],
  _FakeTransactionsProvider? transactionsProvider,
}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
            create: (_) => _FakeAuthProvider()),
        ChangeNotifierProvider<PrivacyProvider>(
          create: (_) => PrivacyProvider(initialHidden: false),
        ),
        ChangeNotifierProvider<TransactionsProvider>(
          create: (_) =>
              transactionsProvider ?? _FakeTransactionsProvider(transactions),
        ),
        ChangeNotifierProvider<ConnectivityService>(
          create: (_) => _Connectivity(),
        ),
        ChangeNotifierProvider<CategoriesProvider>(
          create: (_) => _FakeCategoriesProvider(categories),
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

void _phone(WidgetTester tester, {double width = 390}) {
  tester.view.physicalSize = Size(width * 3, 2532);
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
                    'date': '2025-10-${day.toString().padLeft(2, '0')}',
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
  final l = AppLocalizationsEn();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PreferencesService.resetForTest();
  });

  group('subtitleFor', () {
    final now = DateTime(2026, 11, 11, 15);

    test('subtype, then how long ago the account updated', () {
      expect(
        TransactionsListScreen.subtitleFor(
          l,
          _account('investment',
              subtype: 'brokerage',
              updatedAt: now.subtract(const Duration(hours: 9))),
          now: now,
        ),
        'Brokerage · synced 9h ago',
      );
      expect(
        TransactionsListScreen.subtitleFor(
          l,
          _account('investment',
              subtype: 'roth_ira',
              updatedAt: now.subtract(const Duration(minutes: 5))),
          now: now,
        ),
        'Roth ira · synced 5m ago',
      );
    });

    test('falls back to the type, and drops the time when unknown', () {
      expect(
        TransactionsListScreen.subtitleFor(l, _account('depository'),
            now: now),
        'Bank Account',
      );
      expect(
        TransactionsListScreen.subtitleFor(
          l,
          _account('crypto', updatedAt: now.subtract(const Duration(days: 3))),
          now: now,
        ),
        'Crypto · synced 3d ago',
      );
    });
  });

  testWidgets('bank account: large title, day groups, quiet rows',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(
      TransactionsListScreen(account: _account('depository')),
      transactions: [
        _txn('1', '2025-11-02', r'$10.00'),
        _txn('2', '2025-11-02', r'-$2.50'),
        _txn('3', '2025-11-01', r'$4.00'),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Everyday Checking'), findsWidgets);
    expect(find.byKey(const ValueKey('accountSubtitle')), findsOneWidget);
    expect(find.text('Nov 2, 2025'), findsOneWidget);
    expect(find.text('Nov 1, 2025'), findsOneWidget);
    // Day total in the account's convention: -$10 + $2.50 = -$7.50.
    expect(find.text(r'-$7.50'), findsOneWidget);
    expect(find.byType(SureTransactionRow), findsNWidgets(3));
    expect(find.byType(SureDayHeader), findsNWidgets(2));
    // No currency code under amounts, no ISO dates, no section switcher.
    expect(find.text('USD'), findsNothing);
    expect(find.text('2025-11-02'), findsNothing);
    expect(find.byKey(const ValueKey('accountSectionSwitcher')), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('swipe Categorize picks a category, updates it and reloads',
      (tester) async {
    _phone(tester);
    final patched = <String, Object?>{};
    final service = TransactionSearchService(
      client: MockClient((request) async {
        patched[request.url.path] = jsonDecode(request.body);
        return http.Response(
          jsonEncode({
            'id': '1',
            'name': 'Txn 1',
            'date': '2025-11-02',
            'amount': r'$10.00',
            'currency': 'USD',
            'classification': 'expense',
            'category': {'id': 'cat_food', 'name': 'Food'},
          }),
          200,
        );
      }),
    );
    final provider = _FakeTransactionsProvider([
      _txn('1', '2025-11-02', r'$10.00'),
      _txn('2', '2025-11-02', r'$3.00'),
    ]);
    await tester.pumpWidget(_app(
      TransactionsListScreen(
        account: _account('depository'),
        searchService: service,
      ),
      categories: [
        models.Category(id: 'cat_food', name: 'Food'),
        models.Category(id: 'cat_rent', name: 'Rent'),
      ],
      transactionsProvider: provider,
    ));
    await tester.pumpAndSettle();
    final fetchesBefore = provider.fetches;

    await tester.drag(find.text('Txn 1'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsWidgets);
    await tester.tap(find.text('Categorize').first);
    await tester.pumpAndSettle();
    expect(find.byType(SureSheet), findsOneWidget);
    await tester.tap(find.text('Food').last);
    await tester.pumpAndSettle();

    expect(patched, {
      '/api/v1/transactions/1': {
        'transaction': {'category_id': 'cat_food'},
      },
    });
    expect(find.text('Categorized 1 transaction'), findsOneWidget);
    expect(provider.fetches, fetchesBefore + 1);
  });

  testWidgets('long-press enters multi-select and taps toggle rows',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(
      TransactionsListScreen(account: _account('depository')),
      transactions: [
        _txn('1', '2025-11-02', r'$10.00'),
        _txn('2', '2025-11-02', r'$3.00'),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('accountDeleteSelected')), findsNothing);
    await tester.longPress(find.text('Txn 1'));
    await tester.pumpAndSettle();

    final delete = find.byKey(const ValueKey('accountDeleteSelected'));
    expect(delete, findsOneWidget);
    SureTransactionRow row(String id) => tester.widget<SureTransactionRow>(
        find.ancestor(
            of: find.text('Txn $id'),
            matching: find.byType(SureTransactionRow)));
    expect(row('1').selected, isTrue);
    expect(row('2').selected, isFalse);

    await tester.tap(find.text('Txn 2'));
    await tester.pump();
    expect(row('2').selected, isTrue);

    await tester.tap(find.byKey(const ValueKey('accountSelectToggle')));
    await tester.pumpAndSettle();
    expect(delete, findsNothing);
    expect(row('1').selectionMode, isFalse);
  });

  testWidgets('category filter with no matches offers to clear it',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(
      TransactionsListScreen(account: _account('depository')),
      transactions: [
        _txn('1', '2025-11-02', r'$10.00',
            categoryId: 'cat_food', categoryName: 'Food'),
      ],
      categories: [
        models.Category(id: 'cat_food', name: 'Food'),
        models.Category(id: 'cat_rent', name: 'Rent'),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rent'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('accountNoCategoryMatch')), findsOneWidget);
    expect(find.text(l.transactionsListNoCategoryMatch), findsOneWidget);

    await tester.tap(find.text(l.dspClearFilter));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('accountNoCategoryMatch')), findsNothing);
    expect(find.text('Txn 1'), findsOneWidget);
  });

  testWidgets('no transactions: empty state', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(
      TransactionsListScreen(account: _account('depository')),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SureEmptyState), findsOneWidget);
    expect(find.text(l.transactionsListNoTransactionsYet), findsOneWidget);
    expect(find.text(l.transactionsListEmptyAddFirst), findsOneWidget);
  });

  testWidgets('a long account name ellipsizes at 320 px', (tester) async {
    _phone(tester, width: 320);
    await tester.pumpWidget(_app(
      TransactionsListScreen(
        account: Account(
          id: 'acct_1',
          name: 'A very long account name that cannot possibly fit on one line',
          balance: r'$123,456,789.00',
          currency: 'USD',
          classification: 'asset',
          accountType: 'investment',
          subtype: 'individual_retirement_account_with_a_long_name',
          updatedAt: DateTime.now(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('header: change line with its range, date while scrubbing',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(
      Scaffold(
        body: AccountDetailHeader(
          account: _account('depository'),
          accountDetailService: _chartService(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final change = find.byKey(const ValueKey('accountHeaderChange'));
    expect(change, findsOneWidget);
    expect(
      find.descendant(of: change, matching: find.text(l.accountRangeMonth)),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('accountHeaderBalance')), findsOneWidget);
    expect(find.text(r'$1,000.00'), findsOneWidget);

    final gesture = await tester
        .startGesture(tester.getCenter(find.byType(BalanceHistoryChart)));
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(find.byKey(const ValueKey('accountHeaderScrubDate')), findsOneWidget);
    expect(change, findsNothing);
    // The hero shows the touched day's balance.
    expect(find.text(r'$1,000.00'), findsNothing);
    final date = tester
        .widget<Text>(find.byKey(const ValueKey('accountHeaderScrubDate')))
        .data!;
    expect(date, matches(RegExp(r'^Oct \d+, 2025$')));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(change, findsOneWidget);
    expect(find.text(r'$1,000.00'), findsOneWidget);
  });

  testWidgets('holding row: ticker, "N sh · price", value and gain %',
      (tester) async {
    _phone(tester);
    final holding = AccountHolding.fromJson({
      'id': 'h1',
      'date': '2026-11-10',
      'qty': '781.46',
      'price': r'$102.00',
      'amount': r'$79,708.92',
      'avg_cost': r'$90.00',
      'currency': 'USD',
      'account': {'id': 'acct_1', 'name': 'Brokerage'},
      'security': {'id': 'sec_1', 'ticker': 'VTI', 'name': 'Vanguard Total'},
    });
    await tester.pumpWidget(_app(
      Scaffold(body: HoldingTile(holding: holding)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('VTI'), findsOneWidget);
    expect(find.text('V'), findsOneWidget);
    expect(find.text(r'781.46 sh · $102.00'), findsOneWidget);
    expect(find.text(r'$79,708.92'), findsOneWidget);
    expect(find.text('+13.3%'), findsOneWidget);

    await tester.pumpWidget(_app(
      Scaffold(body: HoldingTile(holding: holding, crypto: true)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('V'), findsNothing);
  });

  testWidgets('an exchange-prefixed ticker shows the bare symbol and a coin',
      (tester) async {
    _phone(tester);
    final holding = AccountHolding.fromJson({
      'id': 'h2',
      'date': '2026-11-10',
      'qty': '781.46',
      'price': r'$102.00',
      'amount': r'$79,708.92',
      'currency': 'USD',
      'security': {'id': 'sec_2', 'ticker': 'CRYPTO:BTC', 'name': 'Bitcoin'},
    });
    await tester.pumpWidget(_app(
      Scaffold(body: HoldingTile(holding: holding)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('BTC'), findsOneWidget);
    expect(find.text('CRYPTO:BTC'), findsNothing);
    // A coin glyph, not the letter "C" from the exchange prefix.
    expect(find.text('C'), findsNothing);
    expect(find.text('B'), findsNothing);
  });

  testWidgets('activity groups trades under day headers', (tester) async {
    _phone(tester);
    final service = AccountDetailService(
      client: MockClient((request) async => http.Response(
            jsonEncode({
              'trades': [
                for (final (i, date) in [
                  '2025-10-03',
                  '2025-10-03',
                  '2025-10-01'
                ].indexed)
                  {
                    'id': 'trade_$i',
                    'date': date,
                    'name': 'Trade $i',
                    'amount': r'-$150.00',
                    'currency': 'USD',
                    'qty': '1',
                    'price': r'$150.00',
                    'security': {'id': 's', 'ticker': 'AAPL'},
                  },
              ],
              'pagination': {
                'page': 1,
                'per_page': 25,
                'total_count': 3,
                'total_pages': 1
              },
            }),
            200,
          )),
    );
    await tester.pumpWidget(_app(
      Scaffold(
        body: TradesList(
          account: _account('investment'),
          accountDetailService: service,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SureDayHeader), findsNWidgets(2));
    expect(find.text('Oct 3, 2025'), findsOneWidget);
    expect(find.text('Oct 1, 2025'), findsOneWidget);
    expect(find.byType(TradeTile), findsNWidgets(3));
    expect(find.text('Buy AAPL'), findsNWidgets(3));
    expect(find.text(r'$150.00'), findsNWidgets(3));
    // The day header carries the date, so rows leave it out.
    expect(find.text(r'1 @ $150.00'), findsNWidgets(3));
  });
}
