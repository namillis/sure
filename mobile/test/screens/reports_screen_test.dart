import 'dart:async';
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
import 'package:sure_mobile/providers/categories_provider.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/screens/cash_flow_category_transactions_screen.dart';
import 'package:sure_mobile/screens/reports_screen.dart';
import 'package:sure_mobile/services/account_detail_service.dart';
import 'package:sure_mobile/services/cash_flow_service.dart';
import 'package:sure_mobile/services/net_worth_history_service.dart';
import 'package:sure_mobile/services/offline_cache_store.dart';
import 'package:sure_mobile/services/preferences_service.dart';
import 'package:sure_mobile/services/spending_vs_normal_service.dart';
import 'package:sure_mobile/services/transactions_service.dart';
import 'package:sure_mobile/theme/sure_colors.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';

import '../support/memory_cache.dart';
import '../support/cash_flow_fixture.dart';
import '../support/fake_categories_service.dart';

class _FakeCategoriesProvider extends CategoriesProvider {
  _FakeCategoriesProvider(this._items);

  final List<Category> _items;

  @override
  List<Category> get categories => _items;

  @override
  Future<void> fetchCategories({required String accessToken}) async {}
}

Account _account(String id,
        {String currency = 'USD',
        String classification = 'asset',
        int cents = 0}) =>
    Account(
      id: id,
      name: id,
      balance: '$cents',
      balanceCents: cents,
      currency: currency,
      classification: classification,
      accountType: 'depository',
    );

final _accounts = [
  _account('a1', cents: 150000),
  _account('l1', classification: 'liability', cents: 20000),
  _account('uk', currency: 'GBP', cents: 1234000),
];

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

const _spendingVsNormal = '''
{
  "currency": "USD", "in_progress": true, "comparable": true,
  "total": "1500.0", "normal_total": "1400.0",
  "categories": [
    {"id": "cat_rent", "name": "Rent", "total": "1000.0", "normal": "757.58", "change": "242.42", "ratio": "0.32"},
    {"id": "cat_food", "name": "Food & Drink", "total": "400.0", "normal": "500.0", "change": "-100.0", "ratio": "-0.2"}
  ]
}
''';

/// A sankey report with [count] expense categories, largest first.
String _manyCategories(int count) {
  final nodes = <Map<String, Object?>>[
    {'id': 'cf', 'name': 'Cash Flow', 'kind': 'cash_flow', 'value': '1000'},
  ];
  final links = <Map<String, Object?>>[];
  for (var i = 0; i < count; i++) {
    nodes.add({
      'id': 'expense_c$i',
      'name': 'Category $i',
      'kind': 'expense',
      'value': '${100 - i}',
      'percentage': '1',
      'category_id': 'c$i',
    });
    links.add({'source': 0, 'target': i + 1, 'value': '${100 - i}'});
  }
  return jsonEncode({
    'currency': 'USD',
    'period': {'start_date': '2026-10-01', 'end_date': '2026-10-19'},
    'sankey': {
      'income': '0',
      'spending': '1000',
      'net_savings': '-1000',
      'nodes': nodes,
      'links': links,
    },
  });
}

const _emptyReport = '''
{"currency": "USD", "period": {"start_date": "2026-10-01", "end_date": "2026-10-19"},
 "sankey": {"income": "0", "spending": "0", "net_savings": "0", "nodes": [], "links": []}}
''';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PreferencesService.resetForTest();
  });

  final cashFlowRequests = <Uri>[];
  final spendingRequests = <Uri>[];
  final balanceRequests = <Uri>[];
  setUp(() {
    cashFlowRequests.clear();
    spendingRequests.clear();
    balanceRequests.clear();
  });

  Widget harness({
    String report = cashFlowSankeyFixture,
    int balancesStatus = 200,
    bool hidden = false,
    ThemeData? theme,
    List<Category> categories = const [],
    Future<void>? cashFlowGate,
    bool pushed = false,
    OfflineCacheStore? netWorthCache,
  }) {
    final cashFlow = CashFlowService(
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/family_settings') {
          return http.Response('{"month_start_day":1}', 200);
        }
        cashFlowRequests.add(request.url);
        if (cashFlowGate != null) await cashFlowGate;
        return http.Response(report, 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );
    final netWorth = NetWorthHistoryService(
      accountDetailService: AccountDetailService(
        client: MockClient((request) async {
          balanceRequests.add(request.url);
          if (balancesStatus != 200) return http.Response('{}', balancesStatus);
          final id = request.url.queryParameters['account_id'];
          return http.Response(
            id == 'a1'
                ? _balances([
                    ['2026-10-10', 150000],
                    ['2026-10-01', 100000],
                  ])
                : _balances([
                    ['2026-10-01', 20000],
                  ]),
            200,
          );
        }),
      ),
      cache: netWorthCache,
    );
    final spending = SpendingVsNormalService(
      client: MockClient((request) async {
        spendingRequests.add(request.url);
        return http.Response(_spendingVsNormal, 200);
      }),
    );
    final screen = ReportsScreen(
          cashFlowService: cashFlow,
          netWorthService: netWorth,
          spendingService: spending,
          transactionsService: TransactionsService(
            client: MockClient((_) async => http.Response(
                '{"transactions":[],"pagination":{"page":1,"per_page":50,'
                '"total_count":0,"total_pages":1}}',
                200)),
          ),
          categoriesService: FakeCategoriesService(),
          accessTokenLoader: (_) async => 'token',
          clock: () => DateTime(2026, 10, 19),
          accounts: _accounts,
          mainCurrency: 'USD',
        );
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PrivacyProvider>.value(
          value: PrivacyProvider(initialHidden: hidden),
        ),
        ChangeNotifierProvider<CategoriesProvider>(
          create: (_) => _FakeCategoriesProvider(categories),
        ),
      ],
      child: MaterialApp(
        theme: theme ?? SureTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Pushed over a first route, the way Home opens it.
        initialRoute: pushed ? '/reports' : '/',
        routes: {
          '/': (_) => pushed ? const SizedBox() : screen,
          '/reports': (_) => screen,
        },
      ),
    );
  }

  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('a saved net worth chart shows when its load fails',
      (tester) async {
    useTallSurface(tester);
    final cache = MemoryCache();
    await tester.pumpWidget(harness(netWorthCache: cache));
    await tester.pumpAndSettle();
    expect(find.text(r'$1,300.00'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
        harness(netWorthCache: cache, balancesStatus: 500));
    await tester.pumpAndSettle();
    expect(find.text(r'$1,300.00'), findsOneWidget);
    expect(find.byKey(const ValueKey('reportsNetWorthChart')), findsOneWidget);
  });

  testWidgets('shows net worth, cash flow and spending for the month',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // Net worth: (1,500.00 - 200.00), up 500.00 from Oct 1.
    expect(find.text(r'$1,300.00'), findsOneWidget);
    expect(find.text(r'+$500.00 since Oct 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('reportsNetWorthChart')), findsOneWidget);
    expect(find.text('Also £12,340.00 in 1 account'), findsOneWidget);
    expect(balanceRequests.map((u) => u.queryParameters['account_id']).toSet(),
        {'a1', 'l1'});
    expect(balanceRequests.first.queryParameters['start_date'], '2026-10-01');

    // Cash flow for the budget month.
    expect(cashFlowRequests.single.queryParameters['start_date'], '2026-10-01');
    expect(cashFlowRequests.single.queryParameters['end_date'], '2026-10-19');
    expect(find.text('In'), findsOneWidget);
    expect(find.text(r'+$5,000.00'), findsOneWidget);
    expect(find.text(r'-$1,500.00'), findsOneWidget);
    expect(find.text(r'$3,500.00'), findsOneWidget);
    expect(find.text('70.0% of In'), findsOneWidget);

    // Spending, largest first, with Rent flagged above normal.
    expect(spendingRequests.single.queryParameters['start_date'], '2026-10-01');
    expect(spendingRequests.single.queryParameters['end_date'], '2026-10-19');
    final rentY = tester.getTopLeft(find.text('Rent')).dy;
    final foodY = tester.getTopLeft(find.text('Food & Drink')).dy;
    expect(rentY, lessThan(foodY));
    expect(find.text('+32%'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('reportsCategory_expense_cat_food')),
        matching: find.textContaining('%'),
      ),
      findsNothing,
    );
  });

  testWidgets('3M reloads every section for 90 days without normal badges',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('reportsPeriod_threeMonths')));
    await tester.pumpAndSettle();

    expect(cashFlowRequests.last.queryParameters['start_date'], '2026-07-21');
    expect(cashFlowRequests.last.queryParameters['end_date'], '2026-10-19');
    expect(balanceRequests.last.queryParameters['start_date'], '2026-07-21');
    expect(spendingRequests, hasLength(1)); // only the Month load
    expect(find.text('+32%'), findsNothing);
  });

  testWidgets('empty period shows the empty state', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(harness(report: _emptyReport));
    await tester.pumpAndSettle();

    expect(find.text('No transactions in this period'), findsOneWidget);
    expect(find.text('Try a longer range.'), findsOneWidget);
    expect(find.byKey(const ValueKey('reportsCashFlow')), findsNothing);
    expect(find.byKey(const ValueKey('reportsSpending')), findsNothing);
    // Net worth does not depend on transactions.
    expect(find.text(r'$1,300.00'), findsOneWidget);
  });

  testWidgets('a net worth failure does not block cash flow', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(harness(balancesStatus: 500));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load net worth history."), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
    expect(find.text(r'+$5,000.00'), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);
  });

  testWidgets('shows the top 8 categories, then all on Show all',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(harness(report: _manyCategories(11)));
    await tester.pumpAndSettle();

    expect(find.text('Category 7'), findsOneWidget);
    expect(find.text('Category 8'), findsNothing);

    await tester.tap(find.text('Show all (11)'));
    await tester.pumpAndSettle();
    expect(find.text('Category 10'), findsOneWidget);

    await tester.tap(find.text('Show less'));
    await tester.pumpAndSettle();
    expect(find.text('Category 8'), findsNothing);
  });

  testWidgets('tapping a category opens its transactions', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rent'));
    await tester.pumpAndSettle();

    final screen = tester.widget<CashFlowCategoryTransactionsScreen>(
        find.byType(CashFlowCategoryTransactionsScreen));
    expect(screen.category.categoryId, 'cat_rent');
    expect(screen.range.startIso, '2026-10-01');
    expect(screen.range.endIso, '2026-10-19');
  });

  testWidgets('privacy mode masks amounts', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(harness(hidden: true));
    await tester.pumpAndSettle();

    expect(find.text(r'$1,300.00'), findsNothing);
    expect(find.text(r'$5,000.00'), findsNothing);
    expect(find.textContaining('••••'), findsWidgets);
  });

  testWidgets('pull to refresh reloads every section', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    final balancesBefore = balanceRequests.length;

    // Not awaited: the indicator completes only as frames are pumped.
    tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
    await tester.pumpAndSettle();

    expect(cashFlowRequests, hasLength(2));
    expect(spendingRequests, hasLength(2));
    expect(balanceRequests.length, balancesBefore * 2);
  });

  group('layout', () {
    testWidgets('large title with a back link to Home when pushed',
        (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness(pushed: true));
      await tester.pumpAndSettle();

      expect(find.byType(SureLargeTitleHeader), findsOneWidget);
      final back = tester.widget<SureBackButton>(find.byType(SureBackButton));
      expect(back.label, 'Home');
      expect(find.text('Reports'), findsWidgets);
    });

    testWidgets('change line: colored amount, then "since" in textSubdued',
        (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      final palette =
          SureColors.of(tester.element(find.byType(ReportsScreen))).palette;
      final text = tester
          .widget<Text>(find.byKey(const ValueKey('reportsNetWorthChange')));
      final spans = (text.textSpan! as TextSpan).children!.cast<TextSpan>();
      expect(spans[0].text, r'+$500.00');
      expect(spans[0].style!.color, palette.success);
      expect(spans[1].text, ' since Oct 1');
      expect(spans[1].style!.color, palette.textSubdued);
    });

    testWidgets('cash flow: range in the header, In/Out/Saved rows',
        (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('reportsCashFlowRange')))
            .data,
        'Oct 1–19',
      );
      final palette =
          SureColors.of(tester.element(find.byType(ReportsScreen))).palette;
      MoneyText amountIn(String key) => tester.widget<MoneyText>(find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(MoneyText),
          ));
      expect(amountIn('reportsIn').color, palette.success);
      expect(amountIn('reportsOut').text, r'-$1,500.00');
      expect(amountIn('reportsOut').color, palette.textPrimary);
      expect(amountIn('reportsSaved').text, r'$3,500.00');
      expect(amountIn('reportsSaved').color, palette.success);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('reportsSaved')),
          matching: find.text('70.0% of In'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('negative savings read in destructive', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness(report: _manyCategories(2)));
      await tester.pumpAndSettle();

      final palette =
          SureColors.of(tester.element(find.byType(ReportsScreen))).palette;
      final saved = tester.widget<MoneyText>(find.descendant(
        of: find.byKey(const ValueKey('reportsSaved')),
        matching: find.byType(MoneyText),
      ));
      expect(saved.text, r'-$1,000.00');
      expect(saved.color, palette.destructive);
    });

    testWidgets('category rows: icon from the category list, bars by share',
        (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(harness(categories: [
        Category(id: 'cat_rent', name: 'Rent', color: '#4da568', icon: 'house'),
      ]));
      await tester.pumpAndSettle();

      final rent = find.byKey(const ValueKey('reportsCategory_expense_cat_rent'));
      final food = find.byKey(const ValueKey('reportsCategory_expense_cat_food'));
      final rentIcon = tester.widget<SureCategoryIcon>(
          find.descendant(of: rent, matching: find.byType(SureCategoryIcon)));
      expect(rentIcon.icon, 'house');
      expect(rentIcon.color, '#4da568');

      double barWidth(Finder row) => tester
          .getSize(find.descendant(
              of: row, matching: find.byKey(const ValueKey('reportsCategoryBar'))))
          .width;
      // Food & Drink (400) is 40% of Rent (1,000), the largest.
      expect(barWidth(food) / barWidth(rent), closeTo(0.4, 0.01));
      expect(tester.getSize(find.descendant(
              of: rent, matching: find.byKey(const ValueKey('reportsCategoryBar'))))
          .height, 4);
    });

    testWidgets('each section shows its own loading state', (tester) async {
      useTallSurface(tester);
      final gate = Completer<void>();
      await tester.pumpWidget(harness(cashFlowGate: gate.future));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(r'$1,300.00'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('reportsCashFlow')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('reportsSpending')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Rent'), findsOneWidget);
    });

    for (final dark in [false, true]) {
      testWidgets('no overflow at 320 px (${dark ? 'dark' : 'light'})',
          (tester) async {
        tester.view.physicalSize = const Size(320, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(harness(
          report: _manyCategories(11),
          theme: dark ? SureTheme.dark : SureTheme.light,
        ));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Show all (11)'), findsOneWidget);
        final palette =
            SureColors.of(tester.element(find.byType(ReportsScreen))).palette;
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          palette.surface,
        );
      });
    }
  });
}
