import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/models/category.dart';
import 'package:sure_mobile/providers/accounts_provider.dart';
import 'package:sure_mobile/providers/categories_provider.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/providers/tags_provider.dart';
import 'package:sure_mobile/providers/transactions_provider.dart';
import 'package:sure_mobile/screens/activity_screen.dart';
import 'package:sure_mobile/services/transaction_search_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';

class _Accounts extends AccountsProvider {
  @override
  Future<bool> fetchAccounts({
    required String accessToken,
    bool forceSync = false,
  }) async =>
      true;
}

class _Categories extends CategoriesProvider {
  @override
  List<Category> get categories => [
        Category(id: 'cat_food', name: 'Food', color: '#00aa00'),
      ];

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

class _Transactions extends TransactionsProvider {
  final deleted = <String>[];

  @override
  Future<bool> deleteTransaction({
    required String accessToken,
    required String transactionId,
  }) async {
    deleted.add(transactionId);
    return true;
  }
}

String _day(int daysAgo) {
  final now = DateTime.now();
  final d = DateTime(now.year, now.month, now.day - daysAgo);
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

Map<String, dynamic> _row(
  String id,
  String name,
  int daysAgo, {
  String amount = r'$12.50',
  String? decimal,
}) =>
    {
      'id': id,
      'date': _day(daysAgo),
      'amount': amount,
      if (decimal != null) 'amount_decimal': decimal,
      'currency': 'USD',
      'name': name,
      'classification': 'expense',
      'split_parent': false,
      'account': {
        'id': 'acct_1',
        'name': 'Everyday Checking',
        'account_type': 'depository',
      },
      'category': {'id': 'cat_coffee', 'name': 'Coffee', 'color': '#e99537'},
      'merchant': null,
      'tags': [],
      'transfer': null,
    };

String _page(List<Map<String, dynamic>> rows) => jsonEncode({
      'transactions': rows,
      'pagination': {
        'page': 1,
        'per_page': 50,
        'total_count': rows.length,
        'total_pages': 1,
      },
    });

Finder _inRows(Finder finder) =>
    find.descendant(of: find.byType(SureTransactionRow), matching: finder);

Future<void> _swipeOpen(WidgetTester tester, String name) async {
  await tester.drag(find.text(name), const Offset(-300, 0));
  await tester.pumpAndSettle();
}

void main() {
  late _Transactions transactions;

  Widget harness(
    TransactionSearchService service, {
    bool hidden = false,
    ThemeData? theme,
  }) {
    transactions = _Transactions();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PrivacyProvider>(
          create: (_) => PrivacyProvider(initialHidden: hidden),
        ),
        ChangeNotifierProvider<AccountsProvider>(create: (_) => _Accounts()),
        ChangeNotifierProvider<CategoriesProvider>(
          create: (_) => _Categories(),
        ),
        ChangeNotifierProvider<TagsProvider>(create: (_) => _Tags()),
        ChangeNotifierProvider<TransactionsProvider>.value(
          value: transactions,
        ),
      ],
      child: MaterialApp(
        theme: theme ?? SureTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ActivityScreen(
          service: service,
          accessTokenLoader: () async => 'token',
        ),
      ),
    );
  }

  TransactionSearchService fixed(List<Map<String, dynamic>> rows) =>
      TransactionSearchService(
        client: MockClient((_) async => http.Response(_page(rows), 200)),
      );

  testWidgets('day sections hold panels of transaction rows', (tester) async {
    await tester.pumpWidget(harness(fixed([
      _row('t1', 'Blue Bottle', 0),
      _row('t2', 'Grocer', 1),
    ])));
    await tester.pumpAndSettle();

    expect(find.text('Activity'), findsWidgets);
    expect(find.byType(SureBackButton), findsNothing);
    expect(find.widgetWithText(SureDayHeader, 'Today'), findsOneWidget);
    expect(find.widgetWithText(SureDayHeader, 'Yesterday'), findsOneWidget);
    expect(find.byType(SurePanel), findsNWidgets(2));
    expect(find.byType(SureTransactionRow), findsNWidgets(2));
    expect(find.text('Blue Bottle'), findsOneWidget);
    expect(find.text('Coffee · Everyday Checking'), findsNWidgets(2));
    expect(_inRows(find.text(r'-$12.50')), findsNWidgets(2));
    // Each day's net total sits in its header.
    expect(
      find.descendant(
        of: find.byType(SureDayHeader),
        matching: find.text(r'-$12.50'),
      ),
      findsNWidgets(2),
    );
    expect(find.byType(SureSearchField), findsOneWidget);
    expect(find.text('Search transactions'), findsOneWidget);
  });

  testWidgets('the summary sums money in and out of the loaded rows',
      (tester) async {
    await tester.pumpWidget(harness(fixed([
      _row('t1', 'Blue Bottle', 0, amount: r'$12.50', decimal: '12.5'),
      _row('t2', 'Paycheck', 0, amount: r'-$100.00', decimal: '-100'),
    ])));
    await tester.pumpAndSettle();

    final summary = find.textContaining(r'In $100.00 · Out $12.50');
    expect(summary, findsOneWidget);
    expect(find.textContaining('loaded'), findsNothing);
    // Today's net: +$100.00 in, $12.50 out.
    expect(
      find.descendant(
        of: find.byType(SureDayHeader),
        matching: find.text(r'+$87.50'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the summary says it covers loaded rows while pages remain',
      (tester) async {
    final service = TransactionSearchService(
      client: MockClient((request) async => http.Response(
            jsonEncode({
              'transactions': [
                for (var i = 0; i < 50; i++) _row('r$i', 'Row $i', 0),
              ],
              'pagination': {
                'page': 1,
                'per_page': 50,
                'total_count': 150,
                'total_pages': 3,
              },
            }),
            200,
          )),
    );
    await tester.pumpWidget(harness(service));
    await tester.pumpAndSettle();
    expect(find.text('Totals for the 50 of 150 loaded'), findsOneWidget);
  });

  testWidgets('scrolling to the end loads the next page', (tester) async {
    final pages = <String>[];
    final service = TransactionSearchService(
      client: MockClient((request) async {
        final page = request.url.queryParameters['page']!;
        pages.add(page);
        return http.Response(
          jsonEncode({
            'transactions': [
              for (var i = 0; i < 50; i++)
                _row('p${page}_$i', 'P$page row $i', 0),
            ],
            'pagination': {
              'page': int.parse(page),
              'per_page': 50,
              'total_count': 100,
              'total_pages': 2,
            },
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(harness(service));
    await tester.pumpAndSettle();
    expect(pages, ['1']);

    await tester.fling(
        find.byType(CustomScrollView), const Offset(0, -6000), 3000);
    await tester.pumpAndSettle();
    expect(pages, ['1', '2']);
  });

  testWidgets('privacy mode masks amounts', (tester) async {
    await tester.pumpWidget(
      harness(fixed([_row('t1', 'Blue Bottle', 0)]), hidden: true),
    );
    await tester.pumpAndSettle();

    expect(find.text(r'-$12.50'), findsNothing);
    expect(_inRows(find.text(r'-$••••')), findsOneWidget);
    expect(find.textContaining(r'$12.50'), findsNothing);
  });

  testWidgets('search is debounced and shows the no-results state',
      (tester) async {
    final searches = <String?>[];
    final service = TransactionSearchService(
      client: MockClient((request) async {
        searches.add(request.url.queryParameters['search']);
        return http.Response(_page([]), 200);
      }),
    );
    await tester.pumpWidget(harness(service));
    await tester.pumpAndSettle();
    expect(searches, [null]);
    expect(find.text('No transactions this month'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'c');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'starbuck');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(searches, [null, 'starbuck']);
    expect(find.text('No matches for "starbuck"'), findsOneWidget);
    expect(
        find.text('Try fewer filters or a longer date range.'), findsOneWidget);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(searches, [null, 'starbuck', null]);
    expect(find.text('No transactions this month'), findsOneWidget);
  });

  testWidgets('the date picker is a sheet; all time with no rows is empty',
      (tester) async {
    final starts = <String?>[];
    final service = TransactionSearchService(
      client: MockClient((request) async {
        starts.add(request.url.queryParameters['start_date']);
        return http.Response(_page([]), 200);
      }),
    );
    await tester.pumpWidget(harness(service));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SureChip, 'This month'));
    await tester.pumpAndSettle();
    expect(find.byType(SureSheet), findsOneWidget);
    await tester.tap(find.text('All time'));
    await tester.pumpAndSettle();

    expect(starts.last, isNull);
    expect(find.text('No transactions yet'), findsOneWidget);
  });

  testWidgets('a failed load shows the error state and retries',
      (tester) async {
    var fail = true;
    final service = TransactionSearchService(
      client: MockClient((_) async {
        if (fail) return http.Response('{}', 500);
        return http.Response(_page([_row('t1', 'Blue Bottle', 0)]), 200);
      }),
    );
    await tester.pumpWidget(harness(service));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load transactions"), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();
    expect(find.text('Blue Bottle'), findsOneWidget);
  });

  testWidgets('swipe Delete confirms and removes the row', (tester) async {
    await tester.pumpWidget(harness(fixed([
      _row('t1', 'Blue Bottle', 0),
      _row('t2', 'Grocer', 0),
    ])));
    await tester.pumpAndSettle();

    await _swipeOpen(tester, 'Blue Bottle');
    await tester.tap(find.text('Delete').first);
    await tester.pumpAndSettle();
    expect(find.text('Delete Transaction'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(transactions.deleted, ['t1']);
    expect(find.text('Blue Bottle'), findsNothing);
    expect(find.text('Grocer'), findsOneWidget);
  });

  testWidgets('swipe Categorize updates just that row', (tester) async {
    final patched = <String>[];
    final service = TransactionSearchService(
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            _page([_row('t1', 'Blue Bottle', 0), _row('t2', 'Grocer', 0)]),
            200,
          );
        }
        final id = request.url.pathSegments.last;
        patched.add(id);
        return http.Response(
          jsonEncode({
            ..._row(id, 'Blue Bottle', 0),
            'category': {'id': 'cat_food', 'name': 'Food', 'color': '#00aa00'},
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(harness(service));
    await tester.pumpAndSettle();

    await _swipeOpen(tester, 'Blue Bottle');
    await tester.tap(find.text('Categorize').first);
    await tester.pumpAndSettle();
    expect(find.byType(SureSheet), findsOneWidget);
    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();

    expect(patched, ['t1']);
    expect(find.text('Food · Everyday Checking'), findsOneWidget);
    expect(find.text('Categorized 1 transaction'), findsOneWidget);
  });

  testWidgets('the select toggle enters multi-select with nothing chosen',
      (tester) async {
    await tester.pumpWidget(harness(fixed([_row('t1', 'Blue Bottle', 0)])));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Select'));
    await tester.pumpAndSettle();
    expect(find.text('0 selected'), findsWidgets);
    await tester.tap(find.text('Blue Bottle'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsWidgets);
  });

  testWidgets('bulk categorize keeps failed rows selected', (tester) async {
    final patched = <String>[];
    final service = TransactionSearchService(
      client: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            _page([_row('t1', 'Blue Bottle', 0), _row('t2', 'Grocer', 0)]),
            200,
          );
        }
        final id = request.url.pathSegments.last;
        patched.add(id);
        if (id == 't2') {
          return http.Response('{"message":"Nope"}', 422);
        }
        return http.Response(
          jsonEncode({
            ..._row(id, 'Blue Bottle', 0),
            'category': {'id': 'cat_food', 'name': 'Food', 'color': '#00aa00'},
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(harness(service));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Blue Bottle'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsWidgets);
    await tester.tap(find.text('Grocer'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsWidgets);

    await tester.tap(find.text('Categorize'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();

    expect(patched, ['t1', 't2']);
    expect(find.text('1 of 2 done. 1 failed and are still selected.'),
        findsOneWidget);
    expect(find.text('1 selected'), findsWidgets);
    expect(find.text('Food · Everyday Checking'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Activity'), findsWidgets);
    expect(find.text('1 selected'), findsNothing);
  });

  for (final dark in [false, true]) {
    testWidgets('fits a 320 px screen (${dark ? 'dark' : 'light'})',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness(
        fixed([
          _row('t1', 'A very long merchant name that will not fit', 0,
              amount: r'$123,456.78', decimal: '123456.78'),
          _row('t2', 'Paycheck', 0,
              amount: r'-$98,765.43', decimal: '-98765.43'),
        ]),
        theme: dark ? SureTheme.dark : SureTheme.light,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SureTransactionRow), findsNWidgets(2));
    });
  }
}
