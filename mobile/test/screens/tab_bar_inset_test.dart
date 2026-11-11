import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/models/account.dart';
import 'package:sure_mobile/models/category.dart';
import 'package:sure_mobile/models/chat.dart';
import 'package:sure_mobile/providers/accounts_provider.dart';
import 'package:sure_mobile/providers/auth_provider.dart';
import 'package:sure_mobile/providers/budgets_provider.dart';
import 'package:sure_mobile/providers/categories_provider.dart';
import 'package:sure_mobile/providers/chat_provider.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/providers/tags_provider.dart';
import 'package:sure_mobile/providers/transactions_provider.dart';
import 'package:sure_mobile/screens/activity_screen.dart';
import 'package:sure_mobile/screens/budgets_screen.dart';
import 'package:sure_mobile/screens/chat_list_screen.dart';
import 'package:sure_mobile/screens/dashboard_screen.dart';
import 'package:sure_mobile/screens/plan_screen.dart';
import 'package:sure_mobile/screens/portfolio_screen.dart';
import 'package:sure_mobile/screens/recurring_screen.dart';
import 'package:sure_mobile/services/account_detail_service.dart';
import 'package:sure_mobile/services/budgets_service.dart';
import 'package:sure_mobile/services/connectivity_service.dart';
import 'package:sure_mobile/services/family_sync_service.dart';
import 'package:sure_mobile/services/insights_service.dart';
import 'package:sure_mobile/services/net_worth_history_service.dart';
import 'package:sure_mobile/services/preferences_service.dart';
import 'package:sure_mobile/services/recurring_transactions_service.dart';
import 'package:sure_mobile/services/spending_vs_normal_service.dart';
import 'package:sure_mobile/services/transaction_search_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';
import 'package:sure_mobile/widgets/trades_list.dart';

import '../support/budget_fixtures.dart';
import '../support/home_fixtures.dart';
import '../support/recurring_fixtures.dart';

/// The shell draws its tab bar over content (`extendBody: true`). Each test
/// pumps a real tab root the same way, with a home indicator, scrolls a long
/// list to the end and checks its last item ends above the bar.

class _Categories extends CategoriesProvider {
  @override
  List<Category> get categories => [Category(id: 'c1', name: 'Coffee')];
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchCategories({required String accessToken}) async {}
}

class _Tags extends TagsProvider {
  @override
  Future<void> fetchTags({
    required String accessToken,
    bool forceRefresh = false,
  }) async {}
}

class _Chats extends ChatProvider {
  _Chats(this._items);
  final List<Chat> _items;
  @override
  List<Chat> get chats => _items;
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;
  @override
  bool get hasIncompleteChatList => false;
  @override
  Future<void> fetchChats({
    required String accessToken,
    int page = 1,
    int perPage = 25,
  }) async {}
}

const _homeIndicator = 34.0;

String _day(int daysAgo) {
  final d = DateTime.now().subtract(Duration(days: daysAgo));
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

Map<String, dynamic> _txn(int i) => {
      'id': 't$i',
      'date': _day(i ~/ 3),
      'amount': r'$12.50',
      'currency': 'USD',
      'name': 'Txn $i',
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

Map<String, dynamic> _pagination(int count) => {
      'page': 1,
      'per_page': 100,
      'total_count': count,
      'total_pages': 1,
    };

/// One client for every service: long lists where a tab shows one.
MockClient _client() => MockClient((request) async {
      final path = request.url.path;
      http.Response ok(Object body) => http.Response(jsonEncode(body), 200);
      switch (path) {
        case '/api/v1/transactions':
          final perPage =
              int.tryParse(request.url.queryParameters['per_page'] ?? '') ??
                  40;
          final rows = [for (var i = 0; i < perPage.clamp(0, 40); i++) _txn(i)];
          return ok({'transactions': rows, 'pagination': _pagination(40)});
        case '/api/v1/balances':
          return ok({'balances': [], 'pagination': _pagination(0)});
        case '/api/v1/holdings':
          return ok({'holdings': [], 'pagination': _pagination(0)});
        case '/api/v1/trades':
          return ok({
            'trades': [
              for (var i = 0; i < 30; i++)
                {
                  'id': 'trade_$i',
                  'date': '2025-10-0${1 + i % 5}',
                  'name': 'Trade $i',
                  'amount': r'-$100.00',
                  'currency': 'USD',
                  'qty': '1',
                  'price': r'$100.00',
                  'investment_activity_label': 'Buy',
                  'security': {'ticker': 'T$i'},
                  'account': {'id': 'inv_1', 'name': 'Brokerage'},
                },
            ],
            'pagination': _pagination(30),
          });
        case '/api/v1/recurring_transactions':
          return http.Response(
            recurringIndexBody([
              for (var i = 0; i < 30; i++)
                recurringJson(id: 'rt_$i', name: 'Bill $i'),
            ]),
            200,
          );
      }
      return http.Response('{}', 404);
    });

final _accounts = [
  for (final type in [
    'depository',
    'credit_card',
    'investment',
    'crypto',
    'property',
    'vehicle',
    'loan',
    'other_asset',
  ])
    homeAccount('a_$type', type: type, balance: r'$100.00', cents: 10000),
];

Future<void> _pumpInShell(WidgetTester tester, Widget root) async {
  tester.view.physicalSize = const Size(390, 700);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 47, bottom: _homeIndicator);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<PrivacyProvider>(
        create: (_) => PrivacyProvider(initialHidden: false),
      ),
      ChangeNotifierProvider<AccountsProvider>(
        create: (_) => FakeAccountsProvider(
          accounts: _accounts,
          netWorth: r'$800.00',
        ),
      ),
      ChangeNotifierProvider<ConnectivityService>(
        create: (_) => FakeConnectivity(),
      ),
      ChangeNotifierProvider<AuthProvider>(create: (_) => FakeAuth()),
      ChangeNotifierProvider<CategoriesProvider>(create: (_) => _Categories()),
      ChangeNotifierProvider<TagsProvider>(create: (_) => _Tags()),
      ChangeNotifierProvider<TransactionsProvider>(
        create: (_) => TransactionsProvider(),
      ),
      ChangeNotifierProvider<ChatProvider>(
        create: (_) => _Chats([
          for (var i = 0; i < 30; i++)
            Chat(
              id: 'chat_$i',
              title: 'Chat $i',
              createdAt: DateTime(2026, 11, 1),
              updatedAt: DateTime(2026, 11, 1),
            ),
        ]),
      ),
    ],
    child: MaterialApp(
      theme: SureTheme.light,
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      // The shell's layout: the root under a see-through SureTabBar.
      home: Scaffold(
        extendBody: true,
        body: root,
        bottomNavigationBar: SureTabBar(
          currentIndex: 0,
          onSelected: (_) {},
          items: const [
            SureTabItem(icon: SureIcons.house, label: 'Tab 1'),
            SureTabItem(icon: SureIcons.receipt, label: 'Tab 2'),
            SureTabItem(icon: SureIcons.chartPie, label: 'Tab 3'),
            SureTabItem(icon: SureIcons.trendingUp, label: 'Tab 4'),
            SureTabItem(icon: SureIcons.messageCircle, label: 'Tab 5'),
          ],
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Scrolls to the end and checks the last [item] ends above the tab bar.
Future<void> _expectLastClearsBar(WidgetTester tester, Finder item) async {
  for (var i = 0; i < 12; i++) {
    await tester.dragFrom(const Offset(195, 400), const Offset(0, -500));
    await tester.pumpAndSettle();
  }
  final barTop = tester.getTopLeft(find.byType(SureTabBar)).dy;
  expect(barTop, 700 - SureTabBar.height - _homeIndicator);
  expect(item, findsWidgets);
  expect(tester.getBottomLeft(item.last).dy, lessThanOrEqualTo(barTop));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PreferencesService.resetForTest();
  });

  testWidgets('Home: the last account group clears the tab bar',
      (tester) async {
    final client = _client();
    await _pumpInShell(
      tester,
      DashboardScreen(
        accessTokenLoader: () async => 'token',
        netWorthService: NetWorthHistoryService(
            accountDetailService: AccountDetailService(client: client)),
        searchService: TransactionSearchService(client: client),
        insightsService: InsightsService(client: client),
        spendingService: SpendingVsNormalService(client: client),
        syncService: FamilySyncService(client: client),
        clock: () => DateTime(2026, 11, 11, 12),
      ),
    );
    await _expectLastClearsBar(tester, find.byType(SurePanel));
  });

  testWidgets('Activity: the last transaction row clears the tab bar',
      (tester) async {
    await _pumpInShell(
      tester,
      ActivityScreen(
        service: TransactionSearchService(client: _client()),
        accessTokenLoader: () async => 'token',
      ),
    );
    await _expectLastClearsBar(tester, find.byType(SureTransactionRow));
  });

  testWidgets('Plan Budget: the last category row clears the tab bar',
      (tester) async {
    await _pumpInShell(
      tester,
      PlanScreen(
        budgetBuilder: (_) => BudgetsScreen(
          embedded: true,
          provider: BudgetsProvider(
            service: BudgetsService(client: budgetsMockClient()),
            clock: () => DateTime(2026, 10, 19),
          ),
          accessTokenLoader: () async => 'token',
        ),
      ),
    );
    await _expectLastClearsBar(tester, find.byType(SurePanel));
  });

  testWidgets('Plan Recurring: the last recurring row clears the tab bar',
      (tester) async {
    await _pumpInShell(
      tester,
      PlanScreen(
        budgetBuilder: (_) => const SizedBox.shrink(),
        recurringBuilder: (_) => RecurringScreen(
          service: RecurringTransactionsService(client: _client()),
          accessTokenLoader: () async => 'token',
          onUnauthorized: () async {},
          accounts: const <Account>[],
          clock: () => DateTime(2026, 11, 10),
        ),
      ),
    );
    await tester.tap(find.text('Recurring'));
    await tester.pumpAndSettle();
    await _expectLastClearsBar(tester, find.textContaining('Bill '));
  });

  testWidgets('Plan Goals and Bills: the web button clears the tab bar',
      (tester) async {
    await _pumpInShell(
      tester,
      PlanScreen(budgetBuilder: (_) => const SizedBox.shrink()),
    );
    for (final segment in ['Goals', 'Bills']) {
      await tester.tap(find.text(segment));
      await tester.pumpAndSettle();
      await _expectLastClearsBar(tester, find.text('Open on the web'));
    }
  });

  testWidgets('Invest Activity: the last trade clears the tab bar',
      (tester) async {
    await _pumpInShell(
      tester,
      PortfolioScreen(
        accounts: [
          Account(
            id: 'inv_1',
            name: 'Brokerage',
            balance: r'$1,000.00',
            currency: 'USD',
            classification: 'asset',
            accountType: 'investment',
          ),
        ],
        initialCurrency: 'USD',
        accountDetailService: AccountDetailService(client: _client()),
      ),
    );
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    await _expectLastClearsBar(tester, find.byType(TradeTile));
  });

  testWidgets('Assistant: the last chat clears the tab bar', (tester) async {
    await _pumpInShell(tester, const ChatListScreen());
    await _expectLastClearsBar(tester, find.textContaining('Chat '));
  });
}
