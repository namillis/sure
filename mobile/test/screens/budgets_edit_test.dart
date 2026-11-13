import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/providers/budgets_provider.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/providers/server_features_provider.dart';
import 'package:sure_mobile/screens/budget_category_transactions_screen.dart';
import 'package:sure_mobile/screens/budget_edit_sheets.dart';
import 'package:sure_mobile/screens/budgets_screen.dart';
import 'package:sure_mobile/services/budgets_service.dart';
import 'package:sure_mobile/services/preferences_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';

import '../support/budget_fixtures.dart';

/// A budgets server whose GETs serve [budgets] / [categories] as they are at
/// the time of the request, and whose PATCHes go to [onPatch].
class _Server {
  _Server({this.onPatch});

  List<Map<String, dynamic>> budgets = [budgetJson()];
  List<Map<String, dynamic>> categories = octoberCategories();
  final patches = <http.Request>[];
  final gets = <String>[];
  http.Response Function(_Server server, http.Request request)? onPatch;

  Map<String, dynamic> patchBody(int i) =>
      jsonDecode(patches[i].body) as Map<String, dynamic>;

  MockClient get client => MockClient((request) async {
        if (request.method == 'PATCH') {
          patches.add(request);
          return onPatch?.call(this, request) ??
              http.Response('{"error":"unexpected"}', 500);
        }
        gets.add(request.url.path);
        return budgetsMockHandler(budgets: budgets, categories: categories)(
            request);
      });
}

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status);

/// Applies a category PATCH to the fixture, as the server would, and returns
/// the updated line.
http.Response _acceptCategory(_Server server, http.Request request) {
  final id = request.url.pathSegments.last;
  final body = (jsonDecode(request.body) as Map)['budget_category'] as Map;
  final i = server.categories.indexWhere((c) => c['id'] == id);
  final old = server.categories[i];
  final cents = body.containsKey('budgeted_spending')
      ? (double.parse(body['budgeted_spending'] as String) * 100).round()
      : old['budgeted_spending_cents'] as int;
  final category = old['category'] as Map;
  server.categories[i] = budgetCategoryJson(
    id: id,
    categoryId: category['id'] as String,
    name: category['name'] as String,
    parentId: category['parent_id'] as String?,
    budgetedCents: cents,
    actualCents: old['actual_spending_cents'] as int,
  );
  return _json(200, server.categories[i]);
}

http.Response _forbidden(_Server _, http.Request __) => _json(403, {
      'error': 'forbidden',
      'message': 'This budget is shared with you read-only',
    });

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PreferencesService.resetForTest();
  });

  Future<_Server> pumpScreen(
    WidgetTester tester, {
    required bool feature,
    _Server? server,
    Size size = const Size(1080, 2400),
    double ratio = 2.5,
  }) async {
    final s = server ?? _Server();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = ratio;
    addTearDown(tester.view.reset);
    final features = ServerFeaturesProvider()
      ..debugSet(feature ? {ServerFeaturesProvider.budgetsWrite} : {});
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PrivacyProvider>(
            create: (_) => PrivacyProvider(initialHidden: false),
          ),
          ChangeNotifierProvider<ServerFeaturesProvider>.value(value: features),
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
          home: BudgetsScreen(
            provider: BudgetsProvider(
              service: BudgetsService(client: s.client),
              clock: () => DateTime(2026, 10, 19),
            ),
            accessTokenLoader: () async => 'token',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return s;
  }

  Future<void> openCategory(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  Future<void> openTransactionsScreen(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  String fieldText(WidgetTester tester, Key key) {
    final editable = find.descendant(
      of: find.byKey(key),
      matching: find.byType(EditableText),
    );
    return tester.widget<EditableText>(editable).controller.text;
  }

  group('without budgets.write', () {
    testWidgets('a row opens its transactions and the web link stays',
        (tester) async {
      await pumpScreen(tester, feature: false);

      expect(find.text('Edit on web'), findsOneWidget);
      expect(find.text('Edit totals'), findsNothing);

      await tester.tap(find.text('Groceries'));
      await openTransactionsScreen(tester);
      expect(find.byType(BudgetCategoryTransactionsScreen), findsOneWidget);
      expect(find.byType(BudgetCategorySheet), findsNothing);
    });
  });

  group('category sheet', () {
    testWidgets('shows the limit, spending, rollover and transactions',
        (tester) async {
      await pumpScreen(tester, feature: true);
      // Allocation moves stay on the web, so the link stays.
      expect(find.text('Edit on web'), findsOneWidget);

      await openCategory(tester, 'Food');

      expect(find.byType(BudgetCategorySheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BudgetCategorySheet),
          matching: find.text('Food'),
        ),
        findsOneWidget,
      );
      expect(fieldText(tester, const ValueKey('budgetCategoryAmount')),
          '800.00');
      expect(find.text(r'Spent $760.00 this month'), findsOneWidget);
      expect(find.text('Roll over unused amount'), findsOneWidget);
      expect(find.text('Transactions'), findsOneWidget);
    });

    testWidgets('saves a new limit and reloads the month', (tester) async {
      final server = await pumpScreen(
        tester,
        feature: true,
        server: _Server(onPatch: _acceptCategory),
      );
      await openCategory(tester, 'Food');
      final getsBefore = server.gets.length;

      await tester.enterText(
          find.byKey(const ValueKey('budgetCategoryAmount')), '650');
      await tester.tap(find.byKey(const ValueKey('budgetCategorySave')));
      await tester.pumpAndSettle();

      expect(server.patches.single.url.path, '/api/v1/budget_categories/bc_food');
      expect(server.patchBody(0), {
        'budget_category': {'budgeted_spending': '650'},
      });
      expect(find.byType(BudgetCategorySheet), findsNothing);
      expect(find.text('Budget saved'), findsOneWidget);
      // Reloaded: the budget and its lines were fetched again.
      expect(server.gets.length, greaterThan(getsBefore));
      expect(server.gets.sublist(getsBefore),
          contains('/api/v1/budget_categories/bc_food'));
      expect(find.text(r'$760.00 / $650.00'), findsOneWidget);
    });

    testWidgets('a rollover change alone sends only rollover_enabled',
        (tester) async {
      final server = await pumpScreen(
        tester,
        feature: true,
        server: _Server(onPatch: _acceptCategory),
      );
      await openCategory(tester, 'Food');

      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('budgetCategorySave')));
      await tester.pumpAndSettle();

      expect(server.patchBody(0), {
        'budget_category': {'rollover_enabled': true},
      });
    });

    testWidgets('saving without changes sends nothing', (tester) async {
      final server = await pumpScreen(tester, feature: true);
      await openCategory(tester, 'Food');

      await tester.tap(find.byKey(const ValueKey('budgetCategorySave')));
      await tester.pumpAndSettle();

      expect(server.patches, isEmpty);
      expect(find.byType(BudgetCategorySheet), findsNothing);
    });

    testWidgets('Transactions opens the category transactions',
        (tester) async {
      await pumpScreen(tester, feature: true);
      await openCategory(tester, 'Food');

      await tester.tap(find.text('Transactions'));
      await tester.pumpAndSettle();

      final screen = tester.widget<BudgetCategoryTransactionsScreen>(
        find.byType(BudgetCategoryTransactionsScreen),
      );
      expect(screen.categoryIds,
          ['cat_food', 'cat_groceries', 'cat_restaurants']);
      expect(find.byType(BudgetCategorySheet), findsNothing);
    });

    testWidgets('a 422 shows the server message under the amount',
        (tester) async {
      final server = await pumpScreen(
        tester,
        feature: true,
        server: _Server(
          onPatch: (_, __) => _json(422, {
            'error': 'validation_failed',
            'message': 'Budgeted spending is too large',
            'errors': ['Budgeted spending is too large'],
          }),
        ),
      );
      await openCategory(tester, 'Food');
      final getsBefore = server.gets.length;

      await tester.enterText(
          find.byKey(const ValueKey('budgetCategoryAmount')), '99999999');
      await tester.tap(find.byKey(const ValueKey('budgetCategorySave')));
      await tester.pumpAndSettle();

      expect(find.byType(BudgetCategorySheet), findsOneWidget);
      expect(find.text('Budgeted spending is too large'), findsOneWidget);
      final amountY =
          tester.getTopLeft(find.byKey(const ValueKey('budgetCategoryAmount'))).dy;
      final errorY =
          tester.getTopLeft(find.text('Budgeted spending is too large')).dy;
      expect(errorY, greaterThan(amountY));
      // Nothing changed, so nothing reloads.
      expect(server.gets.length, getsBefore);
    });

    testWidgets('a negative or non-numeric amount is refused locally',
        (tester) async {
      final server = await pumpScreen(tester, feature: true);
      await openCategory(tester, 'Food');

      await tester.enterText(
          find.byKey(const ValueKey('budgetCategoryAmount')), 'abc');
      await tester.tap(find.byKey(const ValueKey('budgetCategorySave')));
      await tester.pumpAndSettle();

      expect(find.text('Enter an amount of 0 or more.'), findsOneWidget);
      expect(server.patches, isEmpty);
    });

    testWidgets('a read-only sign-in says so', (tester) async {
      await pumpScreen(
        tester,
        feature: true,
        server: _Server(
          onPatch: (_, __) => _json(403, {
            'error': 'insufficient_scope',
            'message': "This action requires the 'read_write' scope",
          }),
        ),
      );
      await openCategory(tester, 'Food');
      await tester.enterText(
          find.byKey(const ValueKey('budgetCategoryAmount')), '1');
      await tester.tap(find.byKey(const ValueKey('budgetCategorySave')));
      await tester.pumpAndSettle();

      expect(
        find.text('This sign-in can only view data. '
            'Sign in again with full access to make changes.'),
        findsOneWidget,
      );
    });
  });

  group('shared read-only budget (403 forbidden)', () {
    testWidgets('the category sheet locks and the screen stays read-only',
        (tester) async {
      final server = await pumpScreen(
        tester,
        feature: true,
        server: _Server(onPatch: _forbidden),
      );
      await openCategory(tester, 'Food');
      await tester.enterText(
          find.byKey(const ValueKey('budgetCategoryAmount')), '1');
      await tester.tap(find.byKey(const ValueKey('budgetCategorySave')));
      await tester.pumpAndSettle();

      const message = 'This budget is shared with you read-only.';
      expect(
        find.descendant(
          of: find.byType(BudgetCategorySheet),
          matching: find.text(message),
        ),
        findsOneWidget,
      );
      final save = tester.widget<TextButton>(
          find.byKey(const ValueKey('budgetCategorySave')));
      expect(save.onPressed, isNull);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // The screen says so, hides Edit totals and rows open transactions.
      expect(find.byKey(const ValueKey('budgetReadOnlyBanner')), findsOneWidget);
      expect(find.text('Edit totals'), findsNothing);
      await tester.tap(find.text('Groceries'));
      await openTransactionsScreen(tester);
      expect(find.byType(BudgetCategoryTransactionsScreen), findsOneWidget);
      expect(server.patches, hasLength(1));
    });

    testWidgets('the totals sheet shows the same message', (tester) async {
      await pumpScreen(
        tester,
        feature: true,
        server: _Server(onPatch: _forbidden),
      );
      await tester.tap(find.text('Edit totals'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('budgetTotalsIncome')), '6000');
      await tester.tap(find.byKey(const ValueKey('budgetTotalsSave')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(BudgetTotalsSheet),
          matching: find.text('This budget is shared with you read-only.'),
        ),
        findsOneWidget,
      );
    });
  });

  group('totals sheet', () {
    testWidgets('prefills both totals and saves the changed one, then reloads',
        (tester) async {
      final server = await pumpScreen(
        tester,
        feature: true,
        server: _Server(onPatch: (s, request) {
          s.budgets = [
            {...budgetJson(), 'expected_income': r'$6,000.00',
              'expected_income_cents': 600000},
          ];
          return _json(200, s.budgets.single);
        }),
      );
      expect(find.text(r'$5,200.00 / $5,000.00'), findsOneWidget);

      await tester.tap(find.text('Edit totals'));
      await tester.pumpAndSettle();

      expect(find.byType(BudgetTotalsSheet), findsOneWidget);
      expect(find.text('Total budget'), findsOneWidget);
      expect(find.text('Expected income'), findsOneWidget);
      expect(fieldText(tester, const ValueKey('budgetTotalsSpending')),
          '2000.00');
      expect(fieldText(tester, const ValueKey('budgetTotalsIncome')),
          '5000.00');

      await tester.enterText(
          find.byKey(const ValueKey('budgetTotalsIncome')), '6000');
      await tester.tap(find.byKey(const ValueKey('budgetTotalsSave')));
      await tester.pumpAndSettle();

      expect(server.patches.single.url.path, '/api/v1/budgets/budget_oct');
      expect(server.patchBody(0), {
        'budget': {'expected_income': '6000'},
      });
      expect(find.byType(BudgetTotalsSheet), findsNothing);
      expect(find.text(r'$5,200.00 / $6,000.00'), findsOneWidget);
    });

    testWidgets('a 422 shows the server message in the sheet',
        (tester) async {
      await pumpScreen(
        tester,
        feature: true,
        server: _Server(
          onPatch: (_, __) => _json(422, {
            'error': 'validation_failed',
            'message': 'expected_income must be a number greater than or '
                'equal to 0',
          }),
        ),
      );
      await tester.tap(find.text('Edit totals'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('budgetTotalsIncome')), '1');
      await tester.tap(find.byKey(const ValueKey('budgetTotalsSave')));
      await tester.pumpAndSettle();

      expect(find.byType(BudgetTotalsSheet), findsOneWidget);
      expect(
        find.text(
            'expected_income must be a number greater than or equal to 0'),
        findsOneWidget,
      );
    });
  });

  test('budgetEditText formats minor units for the field', () {
    expect(budgetEditText(65050, 'USD', 'en'), '650.50');
    expect(budgetEditText(65050, 'USD', 'sv'), '650,50');
    expect(budgetEditText(1200, 'JPY', 'en'), '1200');
    expect(budgetEditText(0, 'USD', 'en'), '');
    expect(budgetEditText(null, 'USD', 'en'), '');
  });

  testWidgets('both sheets fit a 320 px wide screen', (tester) async {
    await pumpScreen(
      tester,
      feature: true,
      size: const Size(960, 2400),
      ratio: 3,
    );
    await openCategory(tester, 'Restaurants');
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit totals'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
