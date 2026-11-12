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

Future<void> _pump(WidgetTester tester, Widget home, {bool hidden = false}) {
  return tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuthProvider()),
        ChangeNotifierProvider<PrivacyProvider>(
          create: (_) => PrivacyProvider(initialHidden: hidden),
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

/// What a sheet opened by [_openSheet] resolved to.
class _SheetResult {
  bool closed = false;
  bool? value;
}

/// Pumps a page with a button that opens a sheet with [open], taps it and
/// waits for the sheet. The returned holder fills in once the sheet closes.
Future<_SheetResult> _openSheet(
  WidgetTester tester,
  Future<bool?> Function(BuildContext context) open, {
  bool hidden = false,
}) async {
  final result = _SheetResult();
  await _pump(
    tester,
    Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async {
              result.value = await open(context);
              result.closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
    hidden: hidden,
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
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
      await _openSheet(
        tester,
        (context) => showUpdateBalanceSheet(context,
            account: _account, valuationsService: service),
      );

      // The toolbar shows Cancel, the title and Save; the amount field is
      // focused on open.
      expect(find.text(l.dsCancel), findsOneWidget);
      expect(find.text(l.accountActionsUpdateBalance), findsOneWidget);
      final amount = tester.widget<EditableText>(find.descendant(
        of: find.byKey(const ValueKey('updateBalanceAmount')),
        matching: find.byType(EditableText),
      ));
      expect(amount.focusNode.hasFocus, isTrue);

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
      await _openSheet(
        tester,
        (context) => showUpdateBalanceSheet(context,
            account: _account, valuationsService: service),
      );

      await tester.enterText(
          find.byKey(const ValueKey('updateBalanceAmount')), '100');
      await tester.tap(find.text(l.accountActionsSave));
      await tester.pumpAndSettle();
      expect(find.text('Valuation could not be created: Balance is locked'),
          findsOneWidget);
    });

    testWidgets('resolves true to the caller once saved', (tester) async {
      final service = ValuationsService(
        client: MockClient((_) async => http.Response('{"id":"val_1"}', 201)),
      );
      final result = await _openSheet(
        tester,
        (context) => showUpdateBalanceSheet(context,
            account: _account, valuationsService: service),
      );

      await tester.enterText(
          find.byKey(const ValueKey('updateBalanceAmount')), '-25');
      await tester.tap(find.byKey(const ValueKey('updateBalanceSave')));
      await tester.pumpAndSettle();
      expect(result.closed, isTrue);
      expect(result.value, isTrue);
      expect(find.byType(UpdateBalanceScreen), findsNothing);
    });

    testWidgets('Cancel closes with no result', (tester) async {
      final result = await _openSheet(
        tester,
        (context) => showUpdateBalanceSheet(context, account: _account),
      );
      await tester.tap(find.text(l.dsCancel));
      await tester.pumpAndSettle();
      expect(result.closed, isTrue);
      expect(result.value, isNull);
    });

    testWidgets('shows the current balance and the As of date',
        (tester) async {
      await _openSheet(
        tester,
        (context) => showUpdateBalanceSheet(context, account: _account),
      );
      String was() => tester
          .widget<Text>(find.byKey(const ValueKey('updateBalanceWas')))
          .textSpan!
          .toPlainText();
      expect(was(), r'Was $10,000.00');
      expect(find.text(l.ds3fAsOf), findsOneWidget);
      expect(find.text(l.dsToday), findsOneWidget);
    });

    testWidgets('masks the current balance in privacy mode', (tester) async {
      await _openSheet(
        tester,
        (context) => showUpdateBalanceSheet(context, account: _account),
        hidden: true,
      );
      final was = tester
          .widget<Text>(find.byKey(const ValueKey('updateBalanceWas')))
          .textSpan!
          .toPlainText();
      expect(was, startsWith('Was '));
      expect(was, isNot(contains('10,000')));
    });

    testWidgets('fits a 320 px screen', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _openSheet(
        tester,
        (context) => showUpdateBalanceSheet(context, account: _account),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('TradeFormScreen', () {
    testWidgets('validates required fields', (tester) async {
      // Tall enough that the Save button stays built once errors expand.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _openSheet(
        tester,
        (context) => showTradeFormSheet(context,
            account: _account, tradesService: _securitiesOnly()),
      );

      expect(find.text(l.accountActionsAddTrade), findsOneWidget);
      expect(find.byKey(const ValueKey('tradeDelete')), findsNothing);
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
      await _openSheet(
        tester,
        (context) => showTradeFormSheet(context,
            account: _account, tradesService: _securitiesOnly()),
      );
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
      final result = await _openSheet(
        tester,
        (context) => showTradeFormSheet(context,
            account: _account, trade: trade, tradesService: service),
      );

      expect(find.text(l.accountActionsEditTrade), findsOneWidget);
      expect(find.text('AAPL'), findsOneWidget);
      expect(find.text(l.accountActionsEditTradeNote), findsOneWidget);
      expect(find.byKey(const ValueKey('tradeDelete')), findsOneWidget);
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
      expect(result.value, isTrue);
    });

    testWidgets('edit mode deletes after the confirm', (tester) async {
      String? method;
      final service = TradesService(
        client: MockClient((request) async {
          method = request.method;
          return http.Response('{"message":"Trade deleted"}', 200);
        }),
      );
      final trade = AccountTrade(
        id: 'trade_1',
        date: DateTime(2026, 11, 1),
        name: 'Buy 2 shares of AAPL',
        amount: r'$300.00',
        currency: 'USD',
        quantity: '2.0',
        price: r'$150.00',
        activityLabel: 'Buy',
        ticker: 'AAPL',
      );
      final result = await _openSheet(
        tester,
        (context) => openTradeEditor(context,
            account: _account, trade: trade, tradesService: service),
      );

      await tester.ensureVisible(find.byKey(const ValueKey('tradeDelete')));
      await tester.tap(find.text(l.accountActionsDeleteTrade));
      await tester.pumpAndSettle();
      expect(find.text(l.accountActionsDeleteTradeConfirm), findsOneWidget);
      await tester.tap(find.text(l.commonDelete));
      await tester.pumpAndSettle();
      expect(method, 'DELETE');
      expect(result.value, isTrue);
      expect(find.byType(TradeFormScreen), findsNothing);
    });

    testWidgets('fits a 320 px screen', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _openSheet(
        tester,
        (context) => showTradeFormSheet(context,
            account: _account, tradesService: _securitiesOnly()),
      );
      expect(tester.takeException(), isNull);
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
