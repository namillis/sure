import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/models/budget.dart';
import 'package:sure_mobile/providers/budgets_provider.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/providers/server_features_provider.dart';
import 'package:sure_mobile/screens/budget_category_transactions_screen.dart';
import 'package:sure_mobile/screens/budget_edit_sheets.dart';
import 'package:sure_mobile/screens/budget_move_sheet.dart';
import 'package:sure_mobile/screens/budgets_screen.dart';
import 'package:sure_mobile/services/budgets_service.dart';
import 'package:sure_mobile/services/preferences_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/category_picker_sheet.dart';

import '../support/budget_fixtures.dart';

/// A budgets server whose GETs serve [budgets] / [categories] as they are at
/// the time of the request, and whose POSTs go to [onPost].
class _Server {
  _Server({List<Map<String, dynamic>>? budgets, this.onPost})
      : budgets = budgets ?? [budgetJson()];

  List<Map<String, dynamic>> budgets;
  List<Map<String, dynamic>> categories = octoberCategories();
  final posts = <http.Request>[];
  final gets = <String>[];
  http.Response Function(_Server server, http.Request request)? onPost;

  Map<String, dynamic>? postBody(int i) => posts[i].body.isEmpty
      ? null
      : jsonDecode(posts[i].body) as Map<String, dynamic>;

  MockClient get client => MockClient((request) async {
        if (request.method == 'POST') {
          posts.add(request);
          return onPost?.call(this, request) ??
              http.Response('{"error":"unexpected"}', 500);
        }
        gets.add(request.url.path);
        return budgetsMockHandler(budgets: budgets, categories: categories)(
            request);
      });
}

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PreferencesService.resetForTest();
  });

  Future<_Server> pumpScreen(
    WidgetTester tester, {
    Set<String> features = const {
      ServerFeaturesProvider.budgetsWrite,
      ServerFeaturesProvider.budgetsAllocations,
      ServerFeaturesProvider.budgetsPermissions,
    },
    _Server? server,
    Size size = const Size(1080, 2400),
    double ratio = 2.5,
  }) async {
    final s = server ?? _Server();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = ratio;
    addTearDown(tester.view.reset);
    final featuresProvider = ServerFeaturesProvider()..debugSet(features);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PrivacyProvider>(
            create: (_) => PrivacyProvider(initialHidden: false),
          ),
          ChangeNotifierProvider<ServerFeaturesProvider>.value(
            value: featuresProvider,
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

  Future<void> swipe(WidgetTester tester, String name) async {
    await tester.drag(find.text(name), const Offset(-300, 0));
    await tester.pumpAndSettle();
  }

  Future<void> openMove(WidgetTester tester, String name, String id) async {
    await swipe(tester, name);
    await tester.tap(find.descendant(
      of: find.byKey(ValueKey('budget-move-swipe-$id')),
      matching: find.text('Move'),
    ));
    await tester.pumpAndSettle();
  }

  group('move (budgets.allocations)', () {
    testWidgets('without the feature rows have no Move action',
        (tester) async {
      await pumpScreen(
        tester,
        features: {ServerFeaturesProvider.budgetsWrite},
      );
      await swipe(tester, 'Food');
      expect(find.text('Move'), findsNothing);
    });

    testWidgets('moves budget to a picked category and reloads',
        (tester) async {
      final server = await pumpScreen(
        tester,
        server: _Server(onPost: (s, request) {
          final i = s.categories.indexWhere((c) => c['id'] == 'bc_food');
          final j = s.categories.indexWhere((c) => c['id'] == 'bc_transport');
          s.categories[i] = budgetCategoryJson(
            id: 'bc_food',
            categoryId: 'cat_food',
            name: 'Food',
            budgetedCents: 75000,
            actualCents: 76000,
          );
          s.categories[j] = budgetCategoryJson(
            id: 'bc_transport',
            categoryId: 'cat_transport',
            name: 'Transport',
            budgetedCents: 35000,
            actualCents: 12000,
            rolledOverCents: 5000,
          );
          return _json(200, {
            'from': s.categories[i],
            'to': s.categories[j],
            'budget': s.budgets.single,
          });
        }),
      );

      await openMove(tester, 'Transport', 'bc_transport');
      expect(find.byType(BudgetMoveSheet), findsOneWidget);
      // From shows this category and what is left in it.
      expect(find.text(r'$230.00 left'), findsOneWidget);
      // Move is disabled until a target is picked.
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('budgetMoveAction')))
            .onPressed,
        isNull,
      );

      // A different row: open Food instead.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await openMove(tester, 'Food', 'bc_food');

      await tester.tap(find.byKey(const ValueKey('budgetMoveTo')));
      await tester.pumpAndSettle();
      expect(find.byType(CategoryPickerSheet), findsOneWidget);
      // Its own subcategories and itself are not offered.
      final picker = find.byType(CategoryPickerSheet);
      expect(find.descendant(of: picker, matching: find.text('Groceries')),
          findsNothing);
      expect(find.descendant(of: picker, matching: find.text('Food')),
          findsNothing);
      await tester.enterText(
        find.descendant(of: picker, matching: find.byType(TextField)),
        'tra',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('category-bc_transport')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const ValueKey('budgetMoveAmount')), '50');
      final getsBefore = server.gets.length;
      await tester.tap(find.byKey(const ValueKey('budgetMoveAction')));
      await tester.pumpAndSettle();

      expect(server.posts.single.url.path,
          '/api/v1/budgets/budget_oct/budget_categories/move');
      expect(server.postBody(0), {
        'move': {'from_id': 'bc_food', 'to_id': 'bc_transport', 'amount': '50'},
      });
      expect(find.byType(BudgetMoveSheet), findsNothing);
      expect(find.text('Budget moved'), findsOneWidget);
      expect(server.gets.length, greaterThan(getsBefore));
      expect(find.text(r'$760.00 / $750.00'), findsOneWidget);
    });

    testWidgets('a 422 reason shows a plain message', (tester) async {
      await pumpScreen(
        tester,
        server: _Server(
          onPost: (_, __) => _json(422, {
            'error': 'validation_failed',
            'message': 'Not enough budget',
            'errors': ['Not enough budget'],
            'reason': 'insufficient_funds',
          }),
        ),
      );
      await openMove(tester, 'Transport', 'bc_transport');
      await tester.tap(find.byKey(const ValueKey('budgetMoveTo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('category-bc_food')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('budgetMoveAmount')), '9999');
      await tester.tap(find.byKey(const ValueKey('budgetMoveAction')));
      await tester.pumpAndSettle();

      expect(find.byType(BudgetMoveSheet), findsOneWidget);
      expect(find.text("This category doesn't have that much budget to move."),
          findsOneWidget);
    });

    testWidgets('an amount of 0 is refused locally', (tester) async {
      final server = await pumpScreen(tester);
      await openMove(tester, 'Transport', 'bc_transport');
      await tester.tap(find.byKey(const ValueKey('budgetMoveTo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('category-bc_food')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('budgetMoveAmount')), '0');
      await tester.tap(find.byKey(const ValueKey('budgetMoveAction')));
      await tester.pumpAndSettle();

      expect(find.text('Enter an amount greater than 0.'), findsOneWidget);
      expect(server.posts, isEmpty);
    });

    testWidgets('the sheet fits a 320 px wide screen', (tester) async {
      await pumpScreen(tester, size: const Size(960, 2400), ratio: 3);
      await openMove(tester, 'Restaurants', 'bc_restaurants');
      expect(tester.takeException(), isNull);
    });
  });

  test('budgetMoveTargets leaves out the line, its parent and children', () {
    final lines = octoberCategories().map(BudgetCategory.fromJson).toList();
    String names(String id) => budgetMoveTargets(
          lines.firstWhere((c) => c.id == id),
          lines,
        ).map((c) => c.name).join(',');
    expect(names('bc_food'), 'Gifts,Transport');
    expect(names('bc_groceries'), 'Gifts,Restaurants,Transport');
  });

  group('read-only up front (budgets.permissions)', () {
    testWidgets('can_edit false locks the screen before any write',
        (tester) async {
      await pumpScreen(
        tester,
        server: _Server(budgets: [
          {...budgetJson(), 'can_edit': false},
        ]),
      );

      expect(find.byKey(const ValueKey('budgetReadOnlyBanner')), findsOneWidget);
      expect(find.text('Edit totals'), findsNothing);
      await swipe(tester, 'Food');
      expect(find.text('Move'), findsNothing);

      await tester.tap(find.text('Transport'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(BudgetCategoryTransactionsScreen), findsOneWidget);
    });

    testWidgets('can_edit true keeps editing', (tester) async {
      await pumpScreen(
        tester,
        server: _Server(budgets: [
          {...budgetJson(), 'can_edit': true},
        ]),
      );
      expect(find.byKey(const ValueKey('budgetReadOnlyBanner')), findsNothing);
      expect(find.text('Edit totals'), findsOneWidget);
    });
  });

  group('average in the category sheet', () {
    testWidgets('shows the median after the Spent line', (tester) async {
      final server = _Server();
      final i = server.categories.indexWhere((c) => c['id'] == 'bc_food');
      server.categories[i] = {
        ...server.categories[i],
        'median_spent': r'$650.00',
        'median_spent_cents': 65000,
      };
      await pumpScreen(tester, server: server);
      await tester.tap(find.text('Food'));
      await tester.pumpAndSettle();

      expect(find.byType(BudgetCategorySheet), findsOneWidget);
      expect(find.text(r'Spent $760.00 this month · avg $650.00'),
          findsOneWidget);
    });

    testWidgets('omits it when zero or missing', (tester) async {
      final server = _Server();
      final i = server.categories.indexWhere((c) => c['id'] == 'bc_food');
      server.categories[i] = {
        ...server.categories[i],
        'median_spent': r'$0.00',
        'median_spent_cents': 0,
      };
      await pumpScreen(tester, server: server);
      await tester.tap(find.text('Food'));
      await tester.pumpAndSettle();
      expect(find.text(r'Spent $760.00 this month'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transport'));
      await tester.pumpAndSettle();
      expect(find.text(r'Spent $120.00 this month'), findsOneWidget);
    });
  });

  group('empty month (budgets.allocations)', () {
    Map<String, dynamic> octoberBudget() => budgetJson();

    testWidgets('without the feature only the web link shows',
        (tester) async {
      await pumpScreen(
        tester,
        features: {ServerFeaturesProvider.budgetsWrite},
        server: _Server(budgets: []),
      );
      expect(find.text('Set up on the web'), findsOneWidget);
      expect(find.text('Copy September'), findsNothing);
      expect(find.text('Start from scratch'), findsNothing);
    });

    testWidgets('Copy posts copy_previous with the web month and loads it',
        (tester) async {
      final server = await pumpScreen(
        tester,
        server: _Server(
          budgets: [],
          onPost: (s, _) {
            s.budgets = [octoberBudget()];
            return _json(201, s.budgets.single);
          },
        ),
      );
      expect(find.text('No budget for October'), findsOneWidget);
      expect(find.text('Copy September'), findsOneWidget);
      expect(find.text('Start from scratch'), findsOneWidget);
      expect(find.text('Set up on the web'), findsOneWidget);

      await tester.tap(find.text('Copy September'));
      await tester.pumpAndSettle();

      expect(server.posts.single.url.path,
          '/api/v1/budgets/oct-2026/copy_previous');
      expect(find.text('No budget for October'), findsNothing);
      expect(find.text('Food'), findsOneWidget);
    });

    testWidgets('Start from scratch posts the month and loads it',
        (tester) async {
      final server = await pumpScreen(
        tester,
        server: _Server(
          budgets: [],
          onPost: (s, _) {
            s.budgets = [budgetJson(initialized: false)];
            return _json(201, s.budgets.single);
          },
        ),
      );
      await tester.tap(find.text('Start from scratch'));
      await tester.pumpAndSettle();

      expect(server.posts.single.url.path, '/api/v1/budgets');
      expect(server.postBody(0), {
        'budget': {'month': '2026-10'},
      });
      expect(find.text('No budget for October'), findsNothing);
    });

    testWidgets('no_source hides Copy and keeps Start', (tester) async {
      final server = await pumpScreen(
        tester,
        server: _Server(
          budgets: [],
          onPost: (_, __) => _json(422, {
            'error': 'no_source',
            'message': 'No previous budget found to copy from',
          }),
        ),
      );
      await tester.tap(find.text('Copy September'));
      await tester.pumpAndSettle();

      expect(find.text("There's no earlier budget to copy."), findsOneWidget);
      expect(find.text('Copy September'), findsNothing);
      expect(find.text('Start from scratch'), findsOneWidget);
      expect(server.posts, hasLength(1));
    });

    testWidgets('already_set_up just reloads', (tester) async {
      final server = await pumpScreen(
        tester,
        server: _Server(
          budgets: [],
          onPost: (s, _) {
            s.budgets = [octoberBudget()];
            return _json(409, {
              'error': 'already_set_up',
              'message': 'This budget has already been set up',
            });
          },
        ),
      );
      await tester.tap(find.text('Copy September'));
      await tester.pumpAndSettle();

      expect(server.posts, hasLength(1));
      expect(find.text('Food'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('fits a 320 px wide screen', (tester) async {
      await pumpScreen(
        tester,
        server: _Server(budgets: []),
        size: const Size(960, 2400),
        ratio: 3,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
