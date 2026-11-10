import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/l10n/app_localizations_en.dart';
import 'package:sure_mobile/models/account.dart';
import 'package:sure_mobile/models/account_trade.dart';
import 'package:sure_mobile/models/family_sync.dart';
import 'package:sure_mobile/providers/auth_provider.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/screens/trade_form_screen.dart';
import 'package:sure_mobile/screens/update_balance_screen.dart';
import 'package:sure_mobile/services/trades_service.dart';
import 'package:sure_mobile/services/valuations_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/account_actions_menu.dart';
import 'package:sure_mobile/widgets/sync_status_chip.dart';

class _FakeAuthProvider extends AuthProvider {
  bool loggedOut = false;

  @override
  Future<String?> getValidAccessToken() async => 'token';

  @override
  Future<void> logout() async => loggedOut = true;
}

final _account = Account(
  id: 'acct_1',
  name: 'Brokerage',
  balance: r'$10,000.00',
  currency: 'USD',
  classification: 'asset',
  accountType: 'investment',
);

Future<void> _pump(WidgetTester tester, Widget home) {
  return tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuthProvider()),
        ChangeNotifierProvider<PrivacyProvider>(
          create: (_) => PrivacyProvider(initialHidden: false),
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
    ),
  );
}

TradesService _securitiesOnly() => TradesService(
      client: MockClient((_) async => http.Response(
            '{"securities":[],"pagination":{"page":1,"per_page":100,'
            '"total_count":0,"total_pages":0}}',
            200,
          )),
    );

void main() {
  final l = AppLocalizationsEn();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('UpdateBalanceScreen', () {
    testWidgets('requires a balance, then posts it', (tester) async {
      Map<String, dynamic>? sent;
      final service = ValuationsService(
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"id":"val_1"}', 201);
        }),
      );
      await _pump(
        tester,
        UpdateBalanceScreen(account: _account, valuationsService: service),
      );

      await tester.tap(find.text(l.accountActionsSave));
      await tester.pumpAndSettle();
      expect(find.text(l.accountActionsBalanceRequired), findsOneWidget);
      expect(sent, isNull);

      await tester.enterText(
          find.byKey(const ValueKey('updateBalanceAmount')), 'abc');
      await tester.tap(find.text(l.accountActionsSave));
      await tester.pumpAndSettle();
      expect(find.text(l.accountActionsInvalidNumber), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('updateBalanceAmount')), '12,500.75');
      await tester.tap(find.text(l.accountActionsSave));
      await tester.pumpAndSettle();
      expect(sent!['valuation']['account_id'], 'acct_1');
      expect(sent!['valuation']['amount'], '12500.75');
      expect(sent!['valuation']['date'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });

    testWidgets('shows the server refusal inline', (tester) async {
      final service = ValuationsService(
        client: MockClient((_) async => http.Response(
              '{"error":"validation_failed","message":"Valuation could not be created",'
              '"errors":["Balance is locked"]}',
              422,
            )),
      );
      await _pump(
        tester,
        UpdateBalanceScreen(account: _account, valuationsService: service),
      );

      await tester.enterText(
          find.byKey(const ValueKey('updateBalanceAmount')), '100');
      await tester.tap(find.text(l.accountActionsSave));
      await tester.pumpAndSettle();
      expect(find.text('Valuation could not be created: Balance is locked'),
          findsOneWidget);
    });
  });

  group('TradeFormScreen', () {
    testWidgets('validates required fields', (tester) async {
      // Tall enough that the Save button stays built once errors expand.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        TradeFormScreen(account: _account, tradesService: _securitiesOnly()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l.accountActionsSave));
      await tester.pumpAndSettle();
      expect(find.text(l.accountActionsSecurityRequired), findsOneWidget);
      expect(find.text(l.accountActionsRequired), findsNWidgets(2));

      await tester.enterText(find.byKey(const ValueKey('tradeQuantity')), '0');
      await tester.enterText(find.byKey(const ValueKey('tradeFee')), '-1');
      await tester.tap(find.text(l.accountActionsSave));
      await tester.pumpAndSettle();
      expect(find.text(l.accountActionsMustBePositive), findsOneWidget);
      expect(find.text(l.accountActionsFeeInvalid), findsOneWidget);
    });

    testWidgets('shows a live total for buys and sells', (tester) async {
      await _pump(
        tester,
        TradeFormScreen(account: _account, tradesService: _securitiesOnly()),
      );
      await tester.pumpAndSettle();
      String total() =>
          tester.widget<Text>(find.byKey(const ValueKey('tradeTotal'))).data!;

      expect(total(), '—');
      await tester.enterText(find.byKey(const ValueKey('tradeQuantity')), '10');
      await tester.pump();
      expect(total(), '—');

      await tester.enterText(find.byKey(const ValueKey('tradePrice')), '150.5');
      await tester.pump();
      expect(total(), r'$1,505.00');

      await tester.enterText(find.byKey(const ValueKey('tradeFee')), '4.95');
      await tester.pump();
      expect(find.text(l.accountActionsTotalCost), findsOneWidget);
      expect(total(), r'$1,509.95');

      await tester.tap(find.text(l.accountActionsSell));
      await tester.pump();
      expect(find.text(l.accountActionsTotalProceeds), findsOneWidget);
      expect(total(), r'$1,500.05');
    });

    testWidgets('edit mode pre-fills the trade and patches it', (tester) async {
      Map<String, dynamic>? sent;
      final service = TradesService(
        client: MockClient((request) async {
          expect(request.method, 'PATCH');
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            '{"id":"trade_1","date":"2026-11-01","amount":"-\$300.00",'
            '"currency":"USD","name":"Sell","qty":"-2.0","price":"\$150.00",'
            '"investment_activity_label":"Sell"}',
            200,
          );
        }),
      );
      final trade = AccountTrade(
        id: 'trade_1',
        date: DateTime(2026, 11, 1),
        name: 'Sell 2 shares of AAPL',
        amount: r'-$300.00',
        currency: 'USD',
        quantity: '-2.0',
        price: r'$150.00',
        activityLabel: 'Sell',
        ticker: 'AAPL',
      );
      await _pump(
        tester,
        TradeFormScreen(account: _account, trade: trade, tradesService: service),
      );

      expect(find.text('AAPL'), findsOneWidget);
      expect(find.byKey(const ValueKey('tradeFee')), findsNothing);
      expect(find.text(l.accountActionsTotalProceeds), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('tradeTotal'))).data,
        r'$300.00',
      );

      await tester.enterText(find.byKey(const ValueKey('tradeQuantity')), '3');
      await tester.tap(find.text(l.accountActionsSave));
      await tester.pumpAndSettle();
      expect(sent, {
        'trade': {
          'type': 'sell',
          'date': '2026-11-01',
          'qty': '3',
          'price': '150',
        },
      });
    });
  });

  test('tradeTotal adds fees to buys and takes them from sells', () {
    expect(tradeTotal(qty: 2, price: 10, fee: 1, side: TradeSide.buy), 21);
    expect(tradeTotal(qty: 2, price: 10, fee: 1, side: TradeSide.sell), 19);
  });

  test('only buys and sells open the edit form', () {
    AccountTrade trade(String qty, String? label) => AccountTrade(
          id: 't',
          date: DateTime(2026),
          name: 'x',
          amount: r'$1.00',
          currency: 'USD',
          quantity: qty,
          price: r'$1.00',
          activityLabel: label,
        );
    expect(TradeFormScreen.canEdit(trade('1.0', 'Buy')), true);
    expect(TradeFormScreen.canEdit(trade('-1.0', null)), true);
    expect(TradeFormScreen.canEdit(trade('0.0', 'Dividend')), false);
    expect(TradeFormScreen.canEdit(trade('1.0', 'Reinvestment')), false);
  });

  test('Add trade is offered on investment and crypto exchange accounts', () {
    Account account(String type, [String? subtype]) => Account(
          id: 'a',
          name: 'a',
          balance: r'$0',
          currency: 'USD',
          accountType: type,
          subtype: subtype,
        );
    expect(AccountActionsMenu.supportsTrades(account('investment')), true);
    expect(AccountActionsMenu.supportsTrades(account('crypto', 'exchange')), true);
    expect(AccountActionsMenu.supportsTrades(account('crypto', 'wallet')), false);
    expect(AccountActionsMenu.supportsTrades(account('depository')), false);
  });

  test('SyncStatusChip.labelFor describes the latest sync', () {
    final now = DateTime(2026, 11, 10, 12);
    FamilySync sync(String status, {DateTime? completedAt}) => FamilySync(
          id: 's',
          status: status,
          createdAt: now.subtract(const Duration(days: 9)),
          completedAt: completedAt,
        );

    expect(SyncStatusChip.labelFor(l, null, now: now), 'Not synced yet');
    expect(SyncStatusChip.labelFor(l, sync('syncing'), now: now), 'Syncing...');
    expect(SyncStatusChip.labelFor(l, sync('stale'), now: now), 'Sync failed');
    expect(
      SyncStatusChip.labelFor(l,
          sync('completed', completedAt: now.subtract(const Duration(seconds: 20))),
          now: now),
      'Synced just now',
    );
    expect(
      SyncStatusChip.labelFor(l,
          sync('completed', completedAt: now.subtract(const Duration(minutes: 5))),
          now: now),
      'Synced 5m ago',
    );
    expect(
      SyncStatusChip.labelFor(l,
          sync('completed', completedAt: now.subtract(const Duration(hours: 3))),
          now: now),
      'Synced 3h ago',
    );
    expect(SyncStatusChip.labelFor(l, sync('completed'), now: now),
        'Synced 9d ago');
  });
}
