import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/models/account.dart';
import 'package:sure_mobile/models/category.dart';
import 'package:sure_mobile/models/merchant.dart';
import 'package:sure_mobile/models/offline_transaction.dart';
import 'package:sure_mobile/models/transaction.dart';
import 'package:sure_mobile/models/transaction_tag.dart';
import 'package:sure_mobile/providers/accounts_provider.dart';
import 'package:sure_mobile/providers/auth_provider.dart';
import 'package:sure_mobile/providers/categories_provider.dart';
import 'package:sure_mobile/providers/merchants_provider.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/providers/server_features_provider.dart';
import 'package:sure_mobile/providers/tags_provider.dart';
import 'package:sure_mobile/providers/transactions_provider.dart';
import 'package:sure_mobile/screens/convert_to_trade_sheet.dart';
import 'package:sure_mobile/screens/transaction_edit_screen.dart';
import 'package:sure_mobile/services/connectivity_service.dart';
import 'package:sure_mobile/services/recurring_transactions_service.dart';
import 'package:sure_mobile/services/trade_conversion_service.dart';
import 'package:sure_mobile/services/transaction_attachments_service.dart';
import 'package:sure_mobile/services/transaction_split_service.dart';
import 'package:sure_mobile/services/transactions_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';

class _Connectivity extends ChangeNotifier implements ConnectivityService {
  @override
  bool get isOnline => true;
  @override
  bool get isOffline => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth extends ChangeNotifier implements AuthProvider {
  @override
  Future<String?> getValidAccessToken() async => 'token';
  @override
  Future<void> logout() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCategories extends ChangeNotifier implements CategoriesProvider {
  @override
  List<Category> get categories => const [];
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchCategories({required String accessToken}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMerchants extends ChangeNotifier implements MerchantsProvider {
  @override
  List<Merchant> get merchants => const [];
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchMerchants({
    required String accessToken,
    bool forceRefresh = false,
  }) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTags extends ChangeNotifier implements TagsProvider {
  @override
  List<TransactionTag> get tags => const [];
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchTags({
    required String accessToken,
    bool forceRefresh = false,
  }) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAccounts extends ChangeNotifier implements AccountsProvider {
  _FakeAccounts(this.accountType, this.canEdit);
  final String accountType;
  final bool? canEdit;
  @override
  List<Account> get accounts => [
        Account(
          id: 'acct_1',
          name: 'Brokerage',
          balance: '\$0.00',
          currency: 'USD',
          classification: 'asset',
          accountType: accountType,
          canEdit: canEdit,
        ),
      ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTransactions extends ChangeNotifier implements TransactionsProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

OfflineTransaction _txn() => OfflineTransaction(
      id: 'txn_1',
      localId: 'local_1',
      accountId: 'acct_1',
      name: 'Buy VTI',
      date: '2026-11-06',
      amount: '\$500.00',
      currency: 'USD',
      nature: 'expense',
      syncStatus: SyncStatus.synced,
    );

Map<String, dynamic> _txnJson(String accountType) => {
      'id': 'txn_1',
      'entry_id': 'entry_1',
      'date': '2026-11-06',
      'amount': '\$500.00',
      'amount_decimal': '500.0',
      'currency': 'USD',
      'name': 'Buy VTI',
      'classification': 'expense',
      'excluded': false,
      'account': {
        'id': 'acct_1',
        'name': 'Brokerage',
        'account_type': accountType,
      },
      'attachments': [
        {
          'id': 'att_1',
          'filename': 'confirm.pdf',
          'content_type': 'application/pdf',
          'byte_size': 100,
          'url': 'https://demo.sure.am/api/v1/attachments/att_1',
        },
      ],
    };

Map<String, dynamic> _formJson({
  bool search = true,
  List<Map<String, dynamic>>? securities,
}) =>
    {
      'transaction_id': 'txn_1',
      'date': '2026-11-06',
      'name': 'Buy VTI',
      'amount': '\$500.00',
      'amount_cents': 50000,
      'currency': 'USD',
      'account': {'id': 'acct_1', 'name': 'Brokerage'},
      'defaults': {'investment_activity_label': 'Buy'},
      'investment_activity_labels': ['Buy', 'Sell'],
      'ticker_search_available': search,
      'security_options': securities ??
          [
            {
              'id': 'sec_vti',
              'ticker': 'VTI',
              'name': 'Vanguard Total Stock Market',
              'exchange_operating_mic': 'ARCX',
              'current_price': '\$250.00',
            },
          ],
    };

class _Server {
  final requests = <http.Request>[];
  Map<String, dynamic> form = _formJson();
  http.Response? formResponse;
  http.Response convertResponse = http.Response('{"id":"trade_1"}', 201);
  String accountType = 'investment';

  late final client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    if (path.endsWith('/convert_to_trade')) {
      if (request.method == 'POST') return convertResponse;
      return formResponse ?? http.Response(jsonEncode(form), 200);
    }
    if (path.endsWith('/recurring_transactions')) {
      return http.Response(jsonEncode({'recurring_transactions': []}), 200);
    }
    if (path.contains('/attachments/')) return http.Response('', 200);
    return http.Response(jsonEncode(_txnJson(accountType)), 200);
  });

  Map<String, dynamic>? get postedTrade {
    final post = requests
        .where((r) => r.method == 'POST' && r.url.path.endsWith('/convert_to_trade'));
    if (post.isEmpty) return null;
    return (jsonDecode(post.single.body) as Map)['trade']
        as Map<String, dynamic>;
  }
}

Widget _app({
  required Widget home,
  Set<String> features = const {},
  String accountType = 'investment',
  bool? canEdit = true,
  Brightness brightness = Brightness.light,
}) {
  final serverFeatures = ServerFeaturesProvider()..debugSet(features);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PrivacyProvider>(
          create: (_) => PrivacyProvider(initialHidden: false)),
      ChangeNotifierProvider<ConnectivityService>(
          create: (_) => _Connectivity()),
      ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuth()),
      ChangeNotifierProvider<CategoriesProvider>(
          create: (_) => _FakeCategories()),
      ChangeNotifierProvider<MerchantsProvider>(
          create: (_) => _FakeMerchants()),
      ChangeNotifierProvider<TagsProvider>(create: (_) => _FakeTags()),
      ChangeNotifierProvider<AccountsProvider>(
          create: (_) => _FakeAccounts(accountType, canEdit)),
      ChangeNotifierProvider<TransactionsProvider>(
          create: (_) => _FakeTransactions()),
      ChangeNotifierProvider<ServerFeaturesProvider>.value(
          value: serverFeatures),
    ],
    child: MaterialApp(
      theme: brightness == Brightness.dark ? SureTheme.dark : SureTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: home),
    ),
  );
}

const _allFeatures = {
  ServerFeaturesProvider.transactionsAttachments,
  ServerFeaturesProvider.transactionsConvertToTrade,
};

Future<({_Server server, List<bool?> results})> _openScreen(
  WidgetTester tester, {
  Set<String> features = _allFeatures,
  String accountType = 'investment',
  bool? canEdit = true,
  double width = 390,
}) async {
  final server = _Server()..accountType = accountType;
  final results = <bool?>[];
  tester.view.physicalSize = Size(width, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // A fresh tree, so a test can open twice.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(_app(
    features: features,
    accountType: accountType,
    canEdit: canEdit,
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          results.add(await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => TransactionEditScreen(
                transaction: _txn(),
                transactionsService: TransactionsService(client: server.client),
                splitService: TransactionSplitService(client: server.client),
                recurringService:
                    RecurringTransactionsService(client: server.client),
                attachmentsService:
                    TransactionAttachmentsService(client: server.client),
                tradeConversionService:
                    TradeConversionService(client: server.client),
              ),
            ),
          ));
        },
        child: const Text('open'),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (server: server, results: results);
}

final _receipts = find.byKey(const ValueKey('transaction-receipts-panel'));
final _convertRow =
    find.byKey(const ValueKey('transaction-convert-to-trade-row'));

/// Opens the sheet straight from a button, for the sheet's own tests.
Future<({_Server server, List<bool?> results})> _openSheet(
  WidgetTester tester, {
  Map<String, dynamic>? form,
  http.Response? formResponse,
  String amountDecimal = '500.0',
  double width = 390,
  Brightness brightness = Brightness.light,
}) async {
  final server = _Server();
  if (form != null) server.form = form;
  server.formResponse = formResponse;
  final results = <bool?>[];
  final transaction = Transaction.fromJson({
    ..._txnJson('investment'),
    'amount_decimal': amountDecimal,
  });
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // A fresh tree, so a test can open twice.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(_app(
    brightness: brightness,
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          results.add(await showSureSheet<bool>(
            context: context,
            builder: (_) => ConvertToTradeSheet(
              transaction: transaction,
              service: TradeConversionService(client: server.client),
            ),
          ));
        },
        child: const Text('open'),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (server: server, results: results);
}

String _selectedSegment(WidgetTester tester) =>
    tester.widget<SureSegmentedControl<String>>(
        find.byType(SureSegmentedControl<String>)).selected;

void main() {
  group('transaction screen', () {
    testWidgets('without the features: no receipts, no convert',
        (tester) async {
      final opened = await _openScreen(tester, features: const {});
      expect(_receipts, findsNothing);
      expect(_convertRow, findsNothing);
      expect(
          opened.server.requests
              .where((r) => r.url.path.contains('attachments')),
          isEmpty);
    });

    testWidgets('with the features on an investment account: both show',
        (tester) async {
      await _openScreen(tester);
      expect(_receipts, findsOneWidget);
      expect(find.text('Receipts'), findsOneWidget);
      expect(find.byKey(const ValueKey('receipt-att_1')), findsOneWidget);
      expect(_convertRow, findsOneWidget);
    });

    testWidgets('convert is hidden on other accounts and read-only shares',
        (tester) async {
      await _openScreen(tester, accountType: 'depository');
      expect(_receipts, findsOneWidget);
      expect(_convertRow, findsNothing);

      await _openScreen(tester, canEdit: false);
      expect(_convertRow, findsNothing);
    });

    testWidgets('converting closes the sheet and the screen', (tester) async {
      final opened = await _openScreen(tester);
      await tester.ensureVisible(_convertRow);
      await tester.tap(_convertRow);
      await tester.pumpAndSettle();
      expect(find.byType(ConvertToTradeSheet), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('convertSecurity-sec_vti')));
      await tester.enterText(
          find.byKey(const ValueKey('convertShares')), '2');
      await tester.tap(find.byKey(const ValueKey('convertSubmit')));
      await tester.pumpAndSettle();

      expect(opened.server.postedTrade, {
        'security_id': 'sec_vti',
        'qty': '2',
        'investment_activity_label': 'Buy',
      });
      expect(find.byType(ConvertToTradeSheet), findsNothing);
      expect(find.byType(TransactionEditScreen), findsNothing);
      expect(opened.results, [true]);
      expect(find.text('Converted'), findsOneWidget);
    });
  });

  group('convert to trade sheet', () {
    testWidgets('an outflow defaults to Buy, an inflow to Sell',
        (tester) async {
      await _openSheet(tester);
      expect(_selectedSegment(tester), 'Buy');
      expect(find.text('VTI'), findsOneWidget);
      expect(
          find.text(
              'Enter shares or price. The other is worked out from the amount.'),
          findsOneWidget);

      // The server's default says Buy; the inflow's own sign wins.
      await _openSheet(tester, amountDecimal: '-500.0');
      expect(_selectedSegment(tester), 'Sell');
    });

    testWidgets('other ticker hint follows ticker_search_available',
        (tester) async {
      await _openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('convertOtherTicker')));
      await tester.pumpAndSettle();
      expect(find.text('e.g. AAPL'), findsOneWidget);

      await _openSheet(tester, form: _formJson(search: false));
      await tester.tap(find.byKey(const ValueKey('convertOtherTicker')));
      await tester.pumpAndSettle();
      expect(find.text('Enter the exact ticker'), findsOneWidget);
    });

    testWidgets('validates before sending', (tester) async {
      final opened = await _openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('convertSubmit')));
      await tester.pumpAndSettle();
      expect(find.text('Choose a security.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('convertSecurity-sec_vti')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('convertSubmit')));
      await tester.pumpAndSettle();
      expect(find.text('Enter shares or price.'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('convertPrice')), '0');
      await tester.tap(find.byKey(const ValueKey('convertSubmit')));
      await tester.pumpAndSettle();
      expect(find.text('Shares and price must be more than zero.'),
          findsOneWidget);
      expect(opened.server.postedTrade, isNull);
    });

    testWidgets('sends a custom ticker with price only, Sell when chosen',
        (tester) async {
      final opened = await _openSheet(tester, form: _formJson(securities: []));
      // No held securities: the ticker field is already open.
      await tester.enterText(find.byKey(const ValueKey('convertTicker')), 'aapl');
      await tester.enterText(
          find.byKey(const ValueKey('convertPrice')), '250.5');
      await tester.tap(find.text('Sell'));
      await tester.tap(find.byKey(const ValueKey('convertSubmit')));
      await tester.pumpAndSettle();
      expect(opened.server.postedTrade, {
        'custom_ticker': 'AAPL',
        'price': '250.5',
        'investment_activity_label': 'Sell',
      });
      expect(opened.results, [true]);
    });

    testWidgets('maps 422 error keys to plain messages', (tester) async {
      final opened = await _openSheet(tester);
      opened.server.convertResponse = http.Response(
        jsonEncode({
          'error': 'security_not_found',
          'message': 'Security not found',
          'errors': ['Security not found'],
        }),
        422,
      );
      await tester.tap(find.byKey(const ValueKey('convertSecurity-sec_vti')));
      await tester.enterText(
          find.byKey(const ValueKey('convertShares')), '1');
      await tester.tap(find.byKey(const ValueKey('convertSubmit')));
      await tester.pumpAndSettle();
      expect(find.text("That security wasn't found."), findsOneWidget);
      expect(find.byType(ConvertToTradeSheet), findsOneWidget);
    });

    testWidgets('a failed load shows the reason and a retry', (tester) async {
      await _openSheet(
        tester,
        formResponse: http.Response(
          jsonEncode({
            'error': 'already_converted',
            'message': 'Already converted',
          }),
          422,
        ),
      );
      expect(find.text('This transaction has already been converted.'),
          findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
    });

    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('fits at 320 px ($brightness)', (tester) async {
        await _openSheet(tester, width: 320, brightness: brightness);
        await tester.tap(find.byKey(const ValueKey('convertOtherTicker')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
