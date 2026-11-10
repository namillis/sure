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
import 'package:sure_mobile/screens/activity_screen.dart';
import 'package:sure_mobile/services/transaction_search_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';

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

String _day(int daysAgo) {
  final now = DateTime.now();
  final d = DateTime(now.year, now.month, now.day - daysAgo);
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

Map<String, dynamic> _row(String id, String name, int daysAgo) => {
      'id': id,
      'date': _day(daysAgo),
      'amount': r'$12.50',
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

void main() {
  Widget harness(TransactionSearchService service, {bool hidden = false}) {
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
      ],
      child: MaterialApp(
        theme: SureTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ActivityScreen(
          service: service,
          accessTokenLoader: () async => 'token',
        ),
      ),
    );
  }

  testWidgets('groups rows under day headers and colors amounts',
      (tester) async {
    final service = TransactionSearchService(
      client: MockClient((_) async => http.Response(
            _page([
              _row('t1', 'Blue Bottle', 0),
              _row('t2', 'Grocer', 1),
            ]),
            200,
          )),
    );
    await tester.pumpWidget(harness(service));
    await tester.pumpAndSettle();

    expect(find.text('Activity'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Blue Bottle'), findsOneWidget);
    expect(find.text('Coffee'), findsNWidgets(2));
    expect(find.text('Everyday Checking'), findsNWidgets(2));
    expect(find.text(r'-$12.50'), findsNWidgets(2));
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
    final service = TransactionSearchService(
      client: MockClient(
        (_) async => http.Response(_page([_row('t1', 'Blue Bottle', 0)]), 200),
      ),
    );
    await tester.pumpWidget(harness(service, hidden: true));
    await tester.pumpAndSettle();

    expect(find.text(r'-$12.50'), findsNothing);
    expect(find.text(r'-$••••'), findsOneWidget);
  });

  testWidgets('search is debounced and sent to the server', (tester) async {
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

    await tester.enterText(find.byType(TextFormField), 'c');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextFormField), 'cof');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(searches, [null, 'cof']);
    expect(find.text('No transactions match.'), findsOneWidget);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(searches, [null, 'cof', null]);
    expect(find.text('No transactions this month'), findsOneWidget);
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
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.text('Grocer'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.text('Categorize'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();

    expect(patched, ['t1', 't2']);
    expect(find.text('1 of 2 done. 1 failed and are still selected.'),
        findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget); // t1's new category chip.

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Activity'), findsOneWidget);
  });
}
