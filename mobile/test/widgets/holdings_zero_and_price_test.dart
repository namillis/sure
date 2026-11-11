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
import 'package:sure_mobile/providers/auth_provider.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/services/account_detail_service.dart';
import 'package:sure_mobile/services/preferences_service.dart';
import 'package:sure_mobile/services/security_prices_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/utils/zero_holdings.dart';
import 'package:sure_mobile/widgets/holdings_list.dart';
import 'package:sure_mobile/widgets/set_price_sheet.dart';

class _FakeAuthProvider extends AuthProvider {
  @override
  Future<String?> getValidAccessToken() async => 'token';

  @override
  Future<void> logout() async {}
}

final _account = Account(
  id: 'acct_1',
  name: 'Brokerage',
  balance: r'$1,000.00',
  currency: 'USD',
  classification: 'asset',
  accountType: 'investment',
);

Map<String, dynamic> _holdingJson(String id, String ticker, String amount) => {
      'id': id,
      'date': '2026-11-10',
      'qty': '10',
      'price': r'$10.00',
      'amount': amount,
      'currency': 'USD',
      'account': {'id': 'acct_1', 'name': 'Brokerage'},
      'security': {'id': 'sec_$id', 'ticker': ticker, 'name': '$ticker Inc'},
    };

AccountHolding _holding(String id, String ticker, String amount) =>
    AccountHolding.fromJson(_holdingJson(id, ticker, amount));

AccountDetailService _holdingsService(List<Map<String, dynamic>> holdings) =>
    AccountDetailService(
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'holdings': holdings,
              'pagination': {
                'page': 1,
                'per_page': 100,
                'total_count': 1,
                'total_pages': 1
              },
            }),
            200,
          )),
    );

Future<void> _pump(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
            create: (_) => _FakeAuthProvider()),
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
        home: Scaffold(body: home),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final l = AppLocalizationsEn();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PreferencesService.resetForTest();
  });

  group('ZeroHoldings', () {
    test('only an amount that parses as zero counts as zero', () {
      expect(ZeroHoldings.isZero(_holding('1', 'A', r'$0.00')), true);
      expect(ZeroHoldings.isZero(_holding('2', 'B', r'$0.01')), false);
      expect(ZeroHoldings.isZero(_holding('3', 'C', 'n/a')), false);
    });

    test('visible keeps order and drops zeros unless shown', () {
      final holdings = [
        _holding('1', 'A', r'$5.00'),
        _holding('2', 'B', r'$0.00'),
        _holding('3', 'C', r'$1.00'),
      ];
      expect(
        ZeroHoldings.visible(holdings, showZero: false).map((h) => h.ticker),
        ['A', 'C'],
      );
      expect(ZeroHoldings.visible(holdings, showZero: true).length, 3);
      expect(ZeroHoldings.zeroCount(holdings), 1);
      expect(ZeroHoldings.zeroLabel('USD', locale: 'en'), r'$0');
    });
  });

  group('HoldingsList zero-value holdings', () {
    testWidgets('hides them behind a footer that toggles and persists',
        (tester) async {
      await _pump(
        tester,
        HoldingsList(
          account: _account,
          accountDetailService: _holdingsService([
            _holdingJson('1', 'AAPL', r'$100.00'),
            _holdingJson('2', 'DEAD', r'$0.00'),
            _holdingJson('3', 'GONE', r'$0.00'),
          ]),
        ),
      );

      expect(find.text('AAPL'), findsOneWidget);
      expect(find.text('DEAD'), findsNothing);
      expect(find.text(l.p3apZeroHoldingsHidden(2, r'$0')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('zeroHoldingsToggle')));
      await tester.pumpAndSettle();
      expect(find.text('DEAD'), findsOneWidget);
      expect(find.text('GONE'), findsOneWidget);
      expect(find.text(l.p3apZeroHoldingsShown(2, r'$0')), findsOneWidget);
      expect(await PreferencesService.instance.getShowZeroHoldings(), true);
    });

    testWidgets('reads the saved choice', (tester) async {
      SharedPreferences.setMockInitialValues(
          {'holdings_show_zero_value': true});
      PreferencesService.resetForTest();
      await _pump(
        tester,
        HoldingsList(
          account: _account,
          accountDetailService:
              _holdingsService([_holdingJson('2', 'DEAD', r'$0.00')]),
        ),
      );
      expect(find.text('DEAD'), findsOneWidget);
      expect(find.text(l.p3apHide), findsOneWidget);
    });

    testWidgets('all-zero list says so instead of looking empty',
        (tester) async {
      await _pump(
        tester,
        HoldingsList(
          account: _account,
          accountDetailService:
              _holdingsService([_holdingJson('2', 'DEAD', r'$0.00')]),
        ),
      );
      expect(find.text(l.holdingsEmpty), findsNothing);
      expect(find.text(l.p3apAllHoldingsZero(r'$0')), findsOneWidget);
      expect(find.text(l.p3apZeroHoldingsHidden(1, r'$0')), findsOneWidget);
    });

    testWidgets('no footer when nothing is zero; rows report taps',
        (tester) async {
      AccountHolding? tapped;
      await _pump(
        tester,
        HoldingsList(
          account: _account,
          accountDetailService:
              _holdingsService([_holdingJson('1', 'AAPL', r'$100.00')]),
          onHoldingTap: (holding) => tapped = holding,
        ),
      );
      expect(find.byKey(const ValueKey('zeroHoldingsToggle')), findsNothing);
      await tester.tap(find.text('AAPL'));
      expect(tapped?.securityId, 'sec_1');
    });
  });

  group('SetPriceSheet', () {
    Future<void> openSheet(
      WidgetTester tester,
      SecurityPricesService service,
      void Function(bool) onResult,
    ) async {
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => onResult(await showSetPriceSheet(
              context,
              holding: _holding('1', 'PRIV', r'$10.00'),
              service: service,
            )),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('validates, then posts today\'s price in the holding currency',
        (tester) async {
      Map<String, dynamic>? sent;
      bool? result;
      await openSheet(
        tester,
        SecurityPricesService(
          client: MockClient((request) async {
            sent = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response('{"security_id":"sec_1","created":1}', 201);
          }),
        ),
        (value) => result = value,
      );

      await tester.tap(find.byKey(const ValueKey('setPriceSave')));
      await tester.pumpAndSettle();
      expect(find.text(l.p3apPriceRequired), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('setPriceAmount')), '-3');
      await tester.tap(find.byKey(const ValueKey('setPriceSave')));
      await tester.pumpAndSettle();
      expect(find.text(l.p3apPriceInvalid), findsOneWidget);
      expect(sent, isNull);

      await tester.enterText(
          find.byKey(const ValueKey('setPriceAmount')), '1,234.5678');
      await tester.tap(find.byKey(const ValueKey('setPriceSave')));
      await tester.pumpAndSettle();

      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      expect(sent, {
        'security_id': 'sec_1',
        'prices': [
          {'date': today, 'price': '1234.5678', 'currency': 'USD'},
        ],
      });
      expect(result, true);
      expect(find.text(l.p3apPriceSaved), findsOneWidget);
    });

    testWidgets('explains the not-self-hosted refusal', (tester) async {
      await openSheet(
        tester,
        SecurityPricesService(
          client: MockClient((_) async => http.Response(
                '{"error":"self_hosted_only","message":"only self-hosted"}',
                403,
              )),
        ),
        (_) {},
      );
      await tester.enterText(find.byKey(const ValueKey('setPriceAmount')), '5');
      await tester.tap(find.byKey(const ValueKey('setPriceSave')));
      await tester.pumpAndSettle();
      expect(find.text(l.p3apPriceSelfHostedOnly), findsOneWidget);
      expect(find.byType(SetPriceSheet), findsOneWidget);
    });

    testWidgets('shows other server errors verbatim', (tester) async {
      await openSheet(
        tester,
        SecurityPricesService(
          client: MockClient((_) async => http.Response(
                '{"error":"validation_failed","message":"Prices were not imported",'
                '"errors":[{"index":null,"message":"prices can only be imported '
                'for a security no provider tracks"}]}',
                422,
              )),
        ),
        (_) {},
      );
      await tester.enterText(find.byKey(const ValueKey('setPriceAmount')), '5');
      await tester.tap(find.byKey(const ValueKey('setPriceSave')));
      await tester.pumpAndSettle();
      expect(
        find.text('Prices were not imported: prices can only be imported for '
            'a security no provider tracks'),
        findsOneWidget,
      );
    });

    testWidgets('a holding without a security does not open', (tester) async {
      bool? result;
      final holding = AccountHolding.fromJson({
        ..._holdingJson('9', 'X', r'$1.00'),
        'security': null,
      });
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await showSetPriceSheet(context, holding: holding),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(result, false);
      expect(find.byType(SetPriceSheet), findsNothing);
    });
  });
}
