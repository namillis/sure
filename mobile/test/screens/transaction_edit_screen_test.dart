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
import 'package:sure_mobile/models/transaction_tag.dart';
import 'package:sure_mobile/providers/accounts_provider.dart';
import 'package:sure_mobile/providers/auth_provider.dart';
import 'package:sure_mobile/providers/categories_provider.dart';
import 'package:sure_mobile/providers/merchants_provider.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/providers/tags_provider.dart';
import 'package:sure_mobile/providers/transactions_provider.dart';
import 'package:sure_mobile/screens/recurring_form_screen.dart';
import 'package:sure_mobile/screens/transaction_edit_screen.dart';
import 'package:sure_mobile/screens/transaction_sheet.dart';
import 'package:sure_mobile/services/connectivity_service.dart';
import 'package:sure_mobile/services/recurring_transactions_service.dart';
import 'package:sure_mobile/services/transaction_split_service.dart';
import 'package:sure_mobile/services/transactions_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';

import '../support/ds_harness.dart';
import '../support/recurring_fixtures.dart';

class _Connectivity extends ChangeNotifier implements ConnectivityService {
  _Connectivity(this.isOnline);
  @override
  final bool isOnline;
  @override
  bool get isOffline => !isOnline;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth extends ChangeNotifier implements AuthProvider {
  int logouts = 0;
  @override
  Future<String?> getValidAccessToken() async => 'token';
  @override
  Future<void> logout() async => logouts++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCategories extends ChangeNotifier implements CategoriesProvider {
  _FakeCategories(this.categories);
  @override
  final List<Category> categories;
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
  @override
  List<Account> get accounts => [
        Account(
          id: 'acct_1',
          name: 'Chase Sapphire',
          balance: '\$0.00',
          currency: 'USD',
          classification: 'liability',
          accountType: 'credit_card',
        ),
      ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTransactions extends ChangeNotifier implements TransactionsProvider {
  bool updateResult = true;
  bool deleteResult = true;
  String? nextError;
  final List<Map<String, Object?>> updates = [];
  final List<String> deletes = [];

  @override
  String? error;

  @override
  Future<bool> updateTransaction({
    required String accessToken,
    required OfflineTransaction transaction,
    String? name,
    String? notes,
    String? categoryId,
    String? merchantId,
    List<String>? tagIds,
    String? date,
    String? amount,
    String? nature,
  }) async {
    updates.add({
      'name': name,
      'notes': notes,
      'categoryId': categoryId,
      'date': date,
      'amount': amount,
      'nature': nature,
    });
    error = updateResult ? null : nextError;
    return updateResult;
  }

  @override
  Future<bool> deleteTransaction({
    required String accessToken,
    required String transactionId,
  }) async {
    deletes.add(transactionId);
    error = deleteResult ? null : nextError;
    return deleteResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _thisYear(String monthDay) => '${DateTime.now().year}-$monthDay';

OfflineTransaction _txn({String? categoryId = 'cat_food'}) =>
    OfflineTransaction(
      id: 'txn_1',
      localId: 'local_1',
      accountId: 'acct_1',
      name: 'Blue Bottle',
      date: _thisYear('11-06'),
      amount: '\$4.50',
      currency: 'USD',
      nature: 'expense',
      categoryId: categoryId,
      categoryName: categoryId == null ? null : 'Coffee',
      syncStatus: SyncStatus.synced,
    );

Map<String, dynamic> _serverJson({bool split = false}) => {
      'id': 'txn_1',
      'entry_id': 'entry_1',
      'date': _thisYear('11-06'),
      'amount': split ? '\$100.00' : '\$4.50',
      'amount_decimal': split ? '100.0' : '4.5',
      'currency': 'USD',
      'name': 'Blue Bottle',
      'classification': 'expense',
      'split_parent': split,
      'account': {'id': 'acct_1', 'name': 'Chase Sapphire'},
    };

final _categories = [
  Category(id: 'cat_food', name: 'Coffee', color: '#e99537', icon: 'coffee'),
  Category(id: 'cat_rent', name: 'Rent', color: '#4da568', icon: 'house'),
];

class _Harness {
  final auth = _FakeAuth();
  final transactions = _FakeTransactions();
  final List<http.Request> recurringRequests = [];
  bool? result;
}

Future<_Harness> _open(
  WidgetTester tester, {
  bool online = true,
  bool split = false,
  Brightness brightness = Brightness.light,
  double width = 390,
  OfflineTransaction? transaction,
  bool asPage = false,
  Map<String, dynamic> serverExtra = const {},
  List<Map<String, dynamic>> recurring = const [],
  bool recurringFails = false,
}) async {
  final h = _Harness();
  final client = MockClient((request) async {
    if (request.url.path.endsWith('/recurring_transactions')) {
      h.recurringRequests.add(request);
      if (request.method == 'POST') {
        final attrs = (jsonDecode(request.body)
            as Map<String, dynamic>)['recurring_transaction'] as Map;
        return http.Response(
          jsonEncode(recurringJson(
            id: 'rt_new',
            name: attrs['name'] as String,
            amount: '\$${attrs['amount']}',
            amountCents: ((attrs['amount'] as num) * 100).round(),
            merchant: {'id': attrs['merchant_id'], 'name': 'Blue Bottle'},
          )),
          201,
        );
      }
      if (recurringFails) return http.Response('{}', 500);
      return http.Response(recurringIndexBody(recurring), 200);
    }
    if (request.url.path.endsWith('/split')) {
      return http.Response(
        jsonEncode({
          'transaction_id': 'txn_1',
          'amount': '\$100.00',
          'amount_decimal': '100.0',
          'currency': 'USD',
          'children': [
            {
              'id': 'c1',
              'name': 'Rent share',
              'amount': '\$60.00',
              'amount_decimal': '60.0',
              'currency': 'USD',
              'category': {'id': 'cat_rent', 'name': 'Rent'},
            },
            {
              'id': 'c2',
              'name': 'Coffee beans',
              'amount': '\$40.00',
              'amount_decimal': '40.0',
              'currency': 'USD',
              'category': {'id': 'cat_food', 'name': 'Coffee'},
            },
          ],
        }),
        200,
      );
    }
    return http.Response(
      jsonEncode({..._serverJson(split: split), ...serverExtra}),
      200,
    );
  });

  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PrivacyProvider>(
          create: (_) => PrivacyProvider(initialHidden: false),
        ),
        ChangeNotifierProvider<ConnectivityService>(
          create: (_) => _Connectivity(online),
        ),
        ChangeNotifierProvider<AuthProvider>.value(value: h.auth),
        ChangeNotifierProvider<CategoriesProvider>(
          create: (_) => _FakeCategories(_categories),
        ),
        ChangeNotifierProvider<MerchantsProvider>(
          create: (_) => _FakeMerchants(),
        ),
        ChangeNotifierProvider<TagsProvider>(create: (_) => _FakeTags()),
        ChangeNotifierProvider<AccountsProvider>(
          create: (_) => _FakeAccounts(),
        ),
        ChangeNotifierProvider<TransactionsProvider>.value(
          value: h.transactions,
        ),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.dark ? SureTheme.dark : SureTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                if (asPage) {
                  h.result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => TransactionEditScreen(
                        transaction: transaction ?? _txn(),
                        transactionsService:
                            TransactionsService(client: client),
                        splitService: TransactionSplitService(client: client),
                        recurringService:
                            RecurringTransactionsService(client: client),
                      ),
                    ),
                  );
                  return;
                }
                h.result = await showTransactionSheet(
                  context,
                  transaction: transaction ?? _txn(),
                  transactionsService: TransactionsService(client: client),
                  splitService: TransactionSplitService(client: client),
                  recurringService:
                      RecurringTransactionsService(client: client),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return h;
}

Finder _save() => find.widgetWithText(TextButton, 'Save');

void main() {
  testWidgets('lays out the hero and the four panels', (tester) async {
    await _open(tester);

    expect(find.byType(TransactionEditScreen), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(_save(), findsOneWidget);

    final hero = tester.widget<SureCategoryIcon>(
      find.byWidgetPredicate(
        (w) => w is SureCategoryIcon && w.size == SureCategoryIcon.heroSize,
      ),
    );
    expect(hero.name, 'Coffee');
    expect(hero.icon, 'coffee');

    expect(find.text('Blue Bottle'), findsOneWidget);
    // A credit card purchase: money out, minus sign, no currency code.
    expect(find.widgetWithText(MoneyText, '-\$4.50'), findsOneWidget);
    expect(find.text('Nov 6 · Chase Sapphire'), findsOneWidget);

    for (final label in [
      'Category',
      'Split transaction',
      'Merchant',
      'Tags',
      'Add a note',
      'Date',
      'Mark as recurring',
      'Budgets and reports',
      'Open on the web',
      'Attachments, transfer matching and more',
      'Delete transaction',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('transaction-category-row')),
        matching: find.text('Coffee'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('transaction-date-row')),
        matching: find.text('Nov 6'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Save sends the edit, plays the success haptic and pops true',
      (tester) async {
    final haptics = recordHaptics(tester);
    final h = await _open(tester);

    await tester.enterText(
        find.byKey(const ValueKey('transaction-name-field')), 'Blue Bottle SF');
    await tester.enterText(
        find.byKey(const ValueKey('transaction-notes-field')), 'Team coffee');
    await tester.tap(_save());
    await tester.pumpAndSettle();

    expect(h.transactions.updates, hasLength(1));
    expect(h.transactions.updates.single['name'], 'Blue Bottle SF');
    expect(h.transactions.updates.single['notes'], 'Team coffee');
    // Unchanged amount and date are not sent.
    expect(h.transactions.updates.single['amount'], isNull);
    expect(h.transactions.updates.single['date'], isNull);
    expect(haptics, contains('HapticFeedbackType.lightImpact'));
    expect(h.result, isTrue);
    expect(find.byType(TransactionEditScreen), findsNothing);
  });

  testWidgets('an empty name blocks Save', (tester) async {
    final h = await _open(tester);

    await tester.enterText(
        find.byKey(const ValueKey('transaction-name-field')), '  ');
    await tester.tap(_save());
    await tester.pumpAndSettle();

    expect(find.text('Name is required'), findsOneWidget);
    expect(h.transactions.updates, isEmpty);
    expect(find.byType(TransactionEditScreen), findsOneWidget);
  });

  testWidgets('tapping the amount edits it, and a zero amount is refused',
      (tester) async {
    final h = await _open(tester);

    expect(
        find.byKey(const ValueKey('transaction-amount-field')), findsNothing);
    await tester.tap(find.bySemanticsLabel('Edit amount'));
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey('transaction-amount-field'));
    expect(field, findsOneWidget);
    expect(find.text('Expense'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);

    await tester.enterText(field, '0');
    await tester.tap(_save());
    await tester.pumpAndSettle();
    expect(h.transactions.updates, isEmpty);

    await tester.enterText(field, '5.25');
    await tester.tap(_save());
    await tester.pumpAndSettle();
    expect(h.transactions.updates.single['amount'], '5.25');
    expect(h.transactions.updates.single['nature'], 'expense');
  });

  testWidgets('an unauthorized save shows session expired and signs out',
      (tester) async {
    final h = await _open(tester);
    h.transactions
      ..updateResult = false
      ..nextError = 'unauthorized';

    await tester.tap(_save());
    await tester.pumpAndSettle();

    expect(find.text('Session expired. Please login again.'), findsOneWidget);
    expect(h.auth.logouts, 1);
    expect(find.byType(TransactionEditScreen), findsOneWidget);
  });

  testWidgets('a failed save shows the server error and stays open',
      (tester) async {
    final h = await _open(tester);
    h.transactions
      ..updateResult = false
      ..nextError = 'Name is too long';

    await tester.tap(_save());
    await tester.pumpAndSettle();

    expect(find.text('Name is too long'), findsOneWidget);
    expect(h.auth.logouts, 0);
  });

  testWidgets('a split shows "Split (2)" and its parts inline', (tester) async {
    await _open(tester, split: true);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('transaction-category-row')),
        matching: find.text('Split (2)'),
      ),
      findsOneWidget,
    );
    expect(find.text('Rent share'), findsOneWidget);
    expect(find.text('Coffee beans'), findsOneWidget);
    expect(find.widgetWithText(MoneyText, '-\$60.00'), findsOneWidget);
    expect(find.widgetWithText(MoneyText, '-\$40.00'), findsOneWidget);
    final dots = tester.widgetList<SureCategoryIcon>(find.byWidgetPredicate(
      (w) => w is SureCategoryIcon && w.size == SureCategoryIcon.dotSize,
    ));
    expect(dots.map((d) => d.color), ['#4da568', '#e99537']);
    // The hero shows the split badge, and the split's fields are locked.
    expect(
      find.byWidgetPredicate((w) =>
          w is SureCategoryIcon &&
          w.size == SureCategoryIcon.heroSize &&
          w.kind == SureCategoryKind.split),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Edit amount'), findsNothing);
    expect(find.text('Split transaction'), findsNothing);
  });

  testWidgets('Delete confirms, deletes and pops true', (tester) async {
    final h = await _open(tester);

    await tester.ensureVisible(find.text('Delete transaction'));
    await tester.tap(find.text('Delete transaction'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Transaction'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(h.transactions.deletes, ['txn_1']);
    expect(h.result, isTrue);
  });

  testWidgets('pushed as a page (existing callers) it saves from the app bar',
      (tester) async {
    final h = await _open(tester, asPage: true);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Delete transaction'), findsOneWidget);
    await tester.tap(_save());
    await tester.pumpAndSettle();
    expect(h.transactions.updates, hasLength(1));
    expect(h.result, isTrue);
  });

  testWidgets('Cancel pops without saving', (tester) async {
    final h = await _open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(h.transactions.updates, isEmpty);
    expect(h.result, isNull);
  });

  testWidgets('offline: shows the banner and disables the web rows',
      (tester) async {
    await _open(tester, online: false);
    expect(
      find.text(
          "You're offline. Changes can be saved once you're back online."),
      findsOneWidget,
    );
    final web = tester.widget<SureListRow>(
      find.widgetWithText(SureListRow, 'Open on the web'),
    );
    expect(web.onTap, isNull);
  });

  group('web parity', () {
    Finder inRow(String key, String text) => find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.text(text),
        );

    const transfer = {
      'id': 'tr_1',
      'amount': '\$4.50',
      'currency': 'USD',
      'other_account': {
        'id': 'acct_2',
        'name': 'Savings',
        'account_type': 'depository',
      },
    };

    testWidgets('a transfer outflow reads "To <account>"', (tester) async {
      await _open(tester, serverExtra: {'transfer': transfer});
      expect(find.byKey(const ValueKey('transaction-transfer-row')),
          findsOneWidget);
      expect(inRow('transaction-transfer-row', 'Transfer'), findsOneWidget);
      expect(inRow('transaction-transfer-row', 'To Savings'), findsOneWidget);
    });

    testWidgets('a transfer inflow reads "From <account>"', (tester) async {
      await _open(tester, serverExtra: {
        'transfer': transfer,
        'amount_decimal': '-4.5',
        'classification': 'income',
      });
      expect(inRow('transaction-transfer-row', 'From Savings'), findsOneWidget);
    });

    testWidgets('no transfer row without a transfer', (tester) async {
      await _open(tester);
      expect(
          find.byKey(const ValueKey('transaction-transfer-row')), findsNothing);
    });

    for (final (kind, excluded, label) in [
      ('standard', false, 'Included'),
      ('one_time', false, 'One-time'),
      ('funds_movement', false, 'Transfer, not counted'),
      ('cc_payment', false, 'Card payment, not counted'),
      ('loan_payment', false, 'Counted as expense'),
      ('investment_contribution', false, 'Counted as expense'),
      ('standard', true, 'Excluded'),
    ]) {
      testWidgets('Budgets and reports: $kind excluded=$excluded -> $label',
          (tester) async {
        await _open(tester, serverExtra: {'kind': kind, 'excluded': excluded});
        expect(inRow('transaction-budgets-row', label), findsOneWidget);
        expect(inRow('transaction-budgets-row', 'Change on the web'),
            findsOneWidget);
        final row = tester.widget<SureListRow>(
            find.byKey(const ValueKey('transaction-budgets-row')));
        expect(row.onTap, isNotNull);
      });
    }

    testWidgets('a matching series shows "Recurring · <name> · cadence"',
        (tester) async {
      await _open(tester, serverExtra: {
        'merchant': {'id': 'm_bb', 'name': 'Blue Bottle'},
      }, recurring: [
        recurringJson(
          id: 'rt_bb',
          name: 'Coffee subscription',
          amount: '\$4.50',
          amountCents: 450,
          merchant: {'id': 'm_bb', 'name': 'Blue Bottle'},
        ),
      ]);

      expect(inRow('transaction-recurring-row', 'Recurring'), findsOneWidget);
      expect(inRow('transaction-recurring-row', 'Coffee subscription'),
          findsOneWidget);
      expect(inRow('transaction-recurring-row', 'Monthly'), findsOneWidget);
      expect(find.text('Mark as recurring'), findsNothing);

      await tester.ensureVisible(
          find.byKey(const ValueKey('transaction-recurring-row')));
      await tester.tap(find.byKey(const ValueKey('transaction-recurring-row')));
      await tester.pumpAndSettle();
      final form =
          tester.widget<RecurringFormScreen>(find.byType(RecurringFormScreen));
      expect(form.existing?.id, 'rt_bb');
      expect(find.text('Edit recurring'), findsOneWidget);
    });

    testWidgets(
        'no match: "Mark as recurring" opens a prefilled form and '
        'a create flips the row', (tester) async {
      final haptics = recordHaptics(tester);
      final h = await _open(tester, serverExtra: {
        'date': '2026-01-31',
        'merchant': {'id': 'm_bb', 'name': 'Blue Bottle'},
      }, recurring: [
        // Same merchant, far-off amount: not a match.
        recurringJson(
          amountCents: 9900,
          merchant: {'id': 'm_bb', 'name': 'Blue Bottle'},
        ),
      ]);

      expect(inRow('transaction-recurring-row', 'Mark as recurring'),
          findsOneWidget);
      await tester.ensureVisible(
          find.byKey(const ValueKey('transaction-recurring-row')));
      await tester.tap(find.byKey(const ValueKey('transaction-recurring-row')));
      await tester.pumpAndSettle();

      final form =
          tester.widget<RecurringFormScreen>(find.byType(RecurringFormScreen));
      expect(form.existing, isNull);
      final prefill = form.prefill!;
      expect(prefill.name, 'Blue Bottle');
      expect(prefill.amount, 4.5);
      expect(prefill.income, isFalse);
      expect(prefill.currency, 'USD');
      expect(prefill.accountId, 'acct_1');
      expect(prefill.merchantId, 'm_bb');
      expect(prefill.expectedDayOfMonth, 31);
      expect(prefill.lastOccurrenceDate, DateTime(2026, 1, 31));
      expect(prefill.nextExpectedDate, DateTime(2026, 2, 28));
      expect(find.text('New recurring'), findsOneWidget);
      Finder inForm(String text) => find.descendant(
            of: find.byType(RecurringFormScreen),
            matching: find.widgetWithText(TextFormField, text),
          );
      expect(inForm('Blue Bottle'), findsOneWidget);
      expect(inForm('4.50'), findsOneWidget);
      expect(inForm('USD'), findsOneWidget);

      await tester.tap(find.descendant(
        of: find.byType(RecurringFormScreen),
        matching: find.widgetWithText(TextButton, 'Save'),
      ));
      await tester.pumpAndSettle();

      final post = h.recurringRequests.singleWhere((r) => r.method == 'POST');
      final attrs = (jsonDecode(post.body)
          as Map<String, dynamic>)['recurring_transaction'] as Map;
      expect(attrs['name'], 'Blue Bottle');
      expect(attrs['amount'], 4.5);
      expect(attrs['currency'], 'USD');
      expect(attrs['account_id'], 'acct_1');
      expect(attrs['merchant_id'], 'm_bb');
      expect(attrs['expected_day_of_month'], 31);
      expect(attrs['last_occurrence_date'], '2026-01-31');
      expect(attrs['next_expected_date'], '2026-02-28');

      expect(find.byType(RecurringFormScreen), findsNothing);
      expect(find.byType(TransactionEditScreen), findsOneWidget);
      expect(inRow('transaction-recurring-row', 'Recurring'), findsOneWidget);
      expect(inRow('transaction-recurring-row', 'Blue Bottle'),
          findsOneWidget);
      expect(inRow('transaction-recurring-row', 'Monthly'), findsOneWidget);
      expect(haptics, contains('HapticFeedbackType.lightImpact'));
      // One list fetch; the flip needs no re-read.
      expect(h.recurringRequests.where((r) => r.method == 'GET'), hasLength(1));
    });

    testWidgets(
        'a failed recurring fetch disables the row, offers a retry '
        'and leaves the rest of the sheet working', (tester) async {
      final h = await _open(tester, recurringFails: true);

      final row = tester.widget<SureListRow>(
          find.byKey(const ValueKey('transaction-recurring-row')));
      expect(row.enabled, isFalse);
      expect(row.onTap, isNull);
      expect(find.text("Couldn't load recurring transactions"), findsOneWidget);
      expect(find.byKey(const ValueKey('transaction-budgets-row')),
          findsOneWidget);

      await tester.tap(_save());
      await tester.pumpAndSettle();
      expect(h.transactions.updates, hasLength(1));
    });

    testWidgets(
        'offline: recurring disabled with a note, nothing fetched, '
        'budgets row hidden', (tester) async {
      final h = await _open(tester, online: false);

      final row = tester.widget<SureListRow>(
          find.byKey(const ValueKey('transaction-recurring-row')));
      expect(row.enabled, isFalse);
      expect(row.onTap, isNull);
      expect(
          find.text('Recurring needs an internet connection.'), findsOneWidget);
      expect(h.recurringRequests, isEmpty);
      expect(
          find.byKey(const ValueKey('transaction-budgets-row')), findsNothing);
    });
  });

  for (final brightness in brightnesses) {
    testWidgets('no overflow at 320 px ($brightness)', (tester) async {
      await _open(
        tester,
        width: 320,
        brightness: brightness,
        split: true,
        transaction: OfflineTransaction(
          id: 'txn_1',
          localId: 'local_1',
          accountId: 'acct_1',
          name: 'A very long merchant description that keeps going and going',
          date: _thisYear('11-06'),
          amount: '\$4.50',
          currency: 'USD',
          nature: 'expense',
          categoryId: 'cat_food',
          categoryName: 'Coffee',
          syncStatus: SyncStatus.synced,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
