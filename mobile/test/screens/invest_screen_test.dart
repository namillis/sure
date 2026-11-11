import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'package:sure_mobile/screens/invest_screen.dart';
import 'package:sure_mobile/screens/portfolio_screen.dart';
import 'package:sure_mobile/services/account_detail_service.dart';
import 'package:sure_mobile/services/preferences_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';
import 'package:sure_mobile/widgets/holdings_list.dart';
import 'package:sure_mobile/widgets/trades_list.dart';

import '../support/ds_harness.dart' show brightnesses;
import '../support/home_fixtures.dart';

class _FakeAuthProvider extends AuthProvider {
  @override
  Future<String?> getValidAccessToken() async => 'token';

  @override
  Future<void> logout() async {}
}

Account _account(String id, String name, String balance, String currency) =>
    Account(
      id: id,
      name: name,
      balance: balance,
      currency: currency,
      classification: 'asset',
      accountType: 'investment',
    );

final _accounts = [
  _account('inv_1', 'Brokerage', r'$1,500.00', 'USD'),
  _account('inv_2', 'Roth IRA', r'$500.00', 'USD'),
  _account('gbp_1', 'ISA', '£300.00', 'GBP'),
];

Map<String, dynamic> _holding(String id, String accountId, String accountName,
        String ticker, String amount, {String currency = 'USD'}) =>
    {
      'id': id,
      'date': '2026-11-10',
      'qty': '10',
      'price': r'$100.00',
      'amount': amount,
      'currency': currency,
      'avg_cost': r'$80.00',
      'security': {'id': 'sec_$ticker', 'ticker': ticker, 'name': ticker},
      'account': {'id': accountId, 'name': accountName},
    };

Map<String, dynamic> _pagination(int page, int totalPages) => {
      'page': page,
      'per_page': 25,
      'total_count': totalPages * 25,
      'total_pages': totalPages,
    };

/// Serves holdings, trades (two pages) and balance history, and records
/// every request.
AccountDetailService _service(List<Uri> requests) => AccountDetailService(
      client: MockClient((request) async {
        requests.add(request.url);
        final path = request.url.path;
        final query = request.url.queryParameters;
        if (path == '/api/v1/holdings') {
          final accountId = query['account_id'];
          final holdings = switch (accountId) {
            'inv_1' => [
                _holding('h1', 'inv_1', 'Brokerage', 'NASDAQ:AAPL', r'$1,000.00'),
                _holding('h0', 'inv_1', 'Brokerage', 'ZERO', r'$0.00'),
              ],
            'inv_2' => [_holding('h2', 'inv_2', 'Roth IRA', 'VTI', r'$300.00')],
            _ => [
                _holding('h3', 'gbp_1', 'ISA', 'VOD', '£200.00',
                    currency: 'GBP'),
              ],
          };
          return http.Response(
            jsonEncode({'holdings': holdings, 'pagination': _pagination(1, 1)}),
            200,
          );
        }
        if (path == '/api/v1/trades') {
          final page = int.parse(query['page'] ?? '1');
          final start = (page - 1) * 25;
          return http.Response(
            jsonEncode({
              'trades': [
                for (var i = start; i < start + 25; i++)
                  {
                    'id': 'trade_$i',
                    'date': i < 2 ? '2025-10-02' : '2025-10-01',
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
              'pagination': _pagination(page, 2),
            }),
            200,
          );
        }
        if (path == '/api/v1/balances') {
          final base = request.url.queryParameters['account_id'] == 'inv_1'
              ? 1000
              : 400;
          return http.Response(
            jsonEncode({
              'balances': [
                for (var day = 1; day <= 10; day++)
                  {
                    'id': 'bal_$day',
                    'date': '2026-11-${day.toString().padLeft(2, '0')}',
                    'currency': 'USD',
                    'balance': '\$${base + day * 10}.00',
                    'balance_cents': (base + day * 10) * 100,
                  },
              ],
              'pagination': _pagination(1, 1),
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    );

Widget _app(
  Widget home, {
  AccountsProvider? accounts,
  bool hidden = false,
  Brightness brightness = Brightness.light,
}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
            create: (_) => _FakeAuthProvider()),
        ChangeNotifierProvider<PrivacyProvider>(
          create: (_) => PrivacyProvider(initialHidden: hidden),
        ),
        ChangeNotifierProvider<AccountsProvider>(
          create: (_) => accounts ?? FakeAccountsProvider(),
        ),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.dark ? SureTheme.dark : SureTheme.light,
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
  tester.view.physicalSize = Size(width * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<List<Uri>> _pumpPortfolio(
  WidgetTester tester, {
  bool hidden = false,
  Brightness brightness = Brightness.light,
  List<Account>? accounts,
}) async {
  final requests = <Uri>[];
  await tester.pumpWidget(_app(
    PortfolioScreen(
      accounts: accounts ?? _accounts,
      initialCurrency: 'USD',
      accountDetailService: _service(requests),
    ),
    hidden: hidden,
    brightness: brightness,
  ));
  await tester.pumpAndSettle();
  return requests;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PreferencesService.resetForTest();
  });

  testWidgets('header: large title, account count, total, change, gain',
      (tester) async {
    _phone(tester);
    await _pumpPortfolio(tester);

    expect(find.text('Invest'), findsWidgets);
    expect(find.byKey(const ValueKey('investSubtitle')), findsOneWidget);
    expect(find.text('2 accounts'), findsOneWidget);
    expect(find.text(r'$2,000.00'), findsOneWidget);
    // History goes 1420 -> 1600 over the range.
    expect(find.byKey(const ValueKey('investChange')), findsOneWidget);
    expect(find.textContaining(r'+$180.00'), findsOneWidget);
    // Cost basis 2 x $800 against $1,300 of holdings.
    expect(find.byKey(const ValueKey('investUnrealized')), findsOneWidget);
    expect(find.textContaining('Unrealized'), findsOneWidget);
    // No ISO dates anywhere.
    expect(find.textContaining('2026-'), findsNothing);
  });

  testWidgets('Allocation is the default tab, with bar and legend',
      (tester) async {
    _phone(tester);
    await _pumpPortfolio(tester);

    final control = tester.widget<SureSegmentedControl<PortfolioSection>>(
        find.byType(SureSegmentedControl<PortfolioSection>));
    expect(control.selected, PortfolioSection.allocation);
    expect(find.byKey(const ValueKey('investAllocationPanel')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('investAllocationBar'))).height,
      6,
    );
    // Every slice fills the bar's height (a regression drew empty slices).
    final slices = find.descendant(
        of: find.byKey(const ValueKey('investAllocationBar')),
        matching: find.byType(ColoredBox));
    expect(slices, findsNWidgets(3));
    for (final e in slices.evaluate()) {
      expect(tester.getSize(find.byWidget(e.widget)).height, 6);
    }
    // The exchange prefix is dropped from the label, as in holding rows.
    expect(find.textContaining('NASDAQ:'), findsNothing);
    // One slice per security (AAPL, VTI; the $0 holding is left out) and
    // cash: $2,000 - $1,300.
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('VTI'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text(r'50.0% · $1,000.00'), findsOneWidget);
    expect(find.text(r'35.0% · $700.00'), findsOneWidget);
    expect(find.byType(HoldingTile), findsNothing);
  });

  testWidgets('Holdings tab: shared rows with account names and zero-value footer',
      (tester) async {
    _phone(tester);
    await _pumpPortfolio(tester);

    await tester.tap(find.text('Holdings'));
    await tester.pumpAndSettle();

    expect(find.byType(HoldingTile), findsNWidgets(2));
    expect(find.textContaining('Brokerage ·'), findsOneWidget);
    expect(find.textContaining('Roth IRA ·'), findsOneWidget);
    expect(find.byType(ZeroHoldingsFooter), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('zeroHoldingsToggle')));
    await tester.pumpAndSettle();
    expect(find.byType(HoldingTile), findsNWidgets(3));
  });

  testWidgets('Activity tab: trades by day, next page on scroll',
      (tester) async {
    _phone(tester);
    final requests = await _pumpPortfolio(tester);

    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();

    expect(find.byType(SureDayHeader), findsWidgets);
    expect(find.byType(SureDayHeader), findsNWidgets(2));
    expect(find.byType(TradeTile), findsWidgets);
    expect(find.text('Buy T0'), findsOneWidget);

    List<String?> tradePages() => [
          for (final uri in requests)
            if (uri.path == '/api/v1/trades') uri.queryParameters['page'],
        ];
    expect(tradePages(), ['1']);

    for (var i = 0; i < 4; i++) {
      await tester.fling(
          find.byType(TradeTile).first, const Offset(0, -3000), 4000);
      await tester.pumpAndSettle();
    }
    expect(tradePages(), ['1', '2']);
  });

  testWidgets('section switcher stays pinned under the nav bar',
      (tester) async {
    _phone(tester);
    await _pumpPortfolio(tester);
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();

    final switcher = find.byKey(const ValueKey('investSectionSwitcher'));
    final navBottom =
        tester.getBottomLeft(find.byKey(const ValueKey('investNavBar'))).dy;
    expect(tester.getTopLeft(switcher).dy, greaterThan(navBottom + 100));

    await tester.fling(
        find.byType(TradeTile).first, const Offset(0, -1500), 3000);
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(switcher).dy, moreOrLessEquals(navBottom));
    expect(find.byKey(const ValueKey('investTotal')).hitTestable(),
        findsNothing);
  });

  testWidgets('currency control switches the portfolio', (tester) async {
    _phone(tester);
    final requests = await _pumpPortfolio(tester);

    expect(find.byKey(const ValueKey('investCurrencyControl')), findsOneWidget);
    await tester.tap(find.text('GBP'));
    await tester.pumpAndSettle();

    expect(
      requests.where((uri) => uri.queryParameters['account_id'] == 'gbp_1'),
      isNotEmpty,
    );
    expect(find.text('1 account'), findsOneWidget);
    expect(find.text('VOD'), findsOneWidget);
  });

  testWidgets('one currency: no currency control', (tester) async {
    _phone(tester);
    await _pumpPortfolio(tester, accounts: _accounts.take(2).toList());
    expect(find.byKey(const ValueKey('investCurrencyControl')), findsNothing);
  });

  testWidgets('hidden amounts are masked', (tester) async {
    _phone(tester);
    await _pumpPortfolio(tester, hidden: true);
    expect(find.textContaining(r'$2,000'), findsNothing);
    expect(find.textContaining(r'$1,000'), findsNothing);
    expect(find.textContaining(r'$700'), findsNothing);
  });

  for (final brightness in brightnesses) {
    testWidgets('fits 320 px without overflow ($brightness)', (tester) async {
      _phone(tester, width: 320);
      await _pumpPortfolio(tester, brightness: brightness);
      expect(tester.takeException(), isNull);
      for (final tab in ['Holdings', 'Activity']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('Invest tab empty state', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(
      const InvestScreen(),
      accounts: FakeAccountsProvider(accounts: [
        Account(
          id: 'chk',
          name: 'Checking',
          balance: r'$10.00',
          currency: 'USD',
          accountType: 'depository',
        ),
      ]),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('investEmpty')), findsOneWidget);
    expect(find.text('No investments yet'), findsOneWidget);
    expect(
      find.text('Connect a brokerage or add an investment account on the web.'),
      findsOneWidget,
    );
    expect(find.text('Open on the web'), findsOneWidget);
    expect(find.text('Invest'), findsWidgets);
  });

  testWidgets('Invest tab load failure offers a retry', (tester) async {
    _phone(tester);
    final accounts = FakeAccountsProvider(error: 'boom');
    await tester.pumpWidget(_app(const InvestScreen(), accounts: accounts));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('investLoadFailed')), findsOneWidget);
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();
    expect(accounts.fetches, 1);
  });
}
