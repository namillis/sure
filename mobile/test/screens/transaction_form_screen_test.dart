import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/l10n/app_localizations_en.dart';
import 'package:sure_mobile/models/account.dart';
import 'package:sure_mobile/models/category.dart';
import 'package:sure_mobile/providers/auth_provider.dart';
import 'package:sure_mobile/providers/categories_provider.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/providers/transactions_provider.dart';
import 'package:sure_mobile/screens/transaction_form_screen.dart';
import 'package:sure_mobile/services/connectivity_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';

class _Auth extends AuthProvider {
  @override
  Future<String?> getValidAccessToken() async => 'token';
}

class _Categories extends CategoriesProvider {
  @override
  List<Category> get categories => [
        Category(id: 'cat_food', name: 'Food', color: '#00aa00'),
        Category(id: 'cat_rent', name: 'Rent', color: '#aa0000'),
      ];

  @override
  Future<void> fetchCategories({required String accessToken}) async {}
}

class _Transactions extends TransactionsProvider {
  final calls = <Map<String, Object?>>[];

  @override
  Future<bool> createTransaction({
    required String accessToken,
    required String accountId,
    required String name,
    required String date,
    required String amount,
    required String currency,
    required String nature,
    String? notes,
    String? categoryId,
    String? categoryName,
    String? merchantId,
    String? merchantName,
    List<String>? tagIds,
    List<String>? tagNames,
  }) async {
    calls.add({
      'accountId': accountId,
      'name': name,
      'date': date,
      'amount': amount,
      'currency': currency,
      'nature': nature,
      'notes': notes,
      'categoryId': categoryId,
    });
    return true;
  }
}

class _Connectivity extends ChangeNotifier implements ConnectivityService {
  _Connectivity(this.isOnline);
  @override
  final bool isOnline;
  @override
  bool get isOffline => !isOnline;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _account = Account(
  id: 'acct_1',
  name: 'Everyday Checking',
  balance: r'$1,200.00',
  currency: 'USD',
  classification: 'asset',
  accountType: 'depository',
);

void main() {
  final l = AppLocalizationsEn();
  late _Transactions transactions;
  bool? closedWith;
  var closed = false;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    closedWith = null;
    closed = false;
  });

  Future<void> open(
    WidgetTester tester, {
    bool online = true,
    bool hidden = false,
  }) async {
    transactions = _Transactions();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth()),
        ChangeNotifierProvider<PrivacyProvider>(
          create: (_) => PrivacyProvider(initialHidden: hidden),
        ),
        ChangeNotifierProvider<CategoriesProvider>(
          create: (_) => _Categories(),
        ),
        ChangeNotifierProvider<TransactionsProvider>.value(value: transactions),
        ChangeNotifierProvider<ConnectivityService>(
          create: (_) => _Connectivity(online),
        ),
      ],
      child: MaterialApp(
        theme: SureTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  closedWith =
                      await showTransactionFormSheet(context, account: _account);
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder field(String key) => find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(EditableText),
      );

  testWidgets('opens as a sheet with the amount focused', (tester) async {
    await open(tester);

    expect(find.text(l.dsCancel), findsOneWidget);
    expect(find.text(l.ds3fNewTransaction), findsOneWidget);
    expect(find.text(l.ds3fAdd), findsOneWidget);
    expect(find.text(l.transactionFormTypeExpense), findsOneWidget);
    expect(find.text(l.transactionFormTypeIncome), findsOneWidget);
    expect(find.text('Everyday Checking'), findsOneWidget);
    expect(find.text(l.transactionFormNoCategory), findsOneWidget);
    expect(find.text(l.dsToday), findsOneWidget);

    final amount = tester.widget<EditableText>(field('transactionFormAmount'));
    expect(amount.focusNode.hasFocus, isTrue);
    expect(amount.keyboardType,
        const TextInputType.numberWithOptions(decimal: true));
  });

  testWidgets('validates the amount inline', (tester) async {
    await open(tester);

    await tester.tap(find.byKey(const ValueKey('transactionFormAdd')));
    await tester.pumpAndSettle();
    expect(find.text(l.transactionFormAmountRequiredPrompt), findsOneWidget);

    await tester.enterText(field('transactionFormAmount'), 'abc');
    await tester.tap(find.byKey(const ValueKey('transactionFormAdd')));
    await tester.pumpAndSettle();
    expect(find.text(l.transactionFormAmountInvalidNumber), findsOneWidget);

    await tester.enterText(field('transactionFormAmount'), '0');
    await tester.tap(find.byKey(const ValueKey('transactionFormAdd')));
    await tester.pumpAndSettle();
    expect(find.text(l.transactionFormAmountTooSmall), findsOneWidget);
    expect(transactions.calls, isEmpty);
  });

  testWidgets('creates the transaction and resolves true', (tester) async {
    await open(tester);

    await tester.tap(find.text(l.transactionFormTypeIncome));
    await tester.enterText(field('transactionFormAmount'), '1,234.50');
    await tester.enterText(field('transactionFormName'), 'Paycheck');

    await tester.tap(find.byKey(const ValueKey('transactionFormCategory')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category-cat_food')));
    await tester.pumpAndSettle();
    expect(find.text('Food'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('transactionFormAdd')));
    await tester.pumpAndSettle();

    expect(transactions.calls, hasLength(1));
    final call = transactions.calls.single;
    expect(call['accountId'], 'acct_1');
    expect(call['name'], 'Paycheck');
    expect(call['amount'], '1234.5');
    expect(call['currency'], 'USD');
    expect(call['nature'], 'income');
    expect(call['categoryId'], 'cat_food');
    expect(call['notes'], 'This transaction via mobile app.');
    expect(call['date'], DateFormat('yyyy-MM-dd').format(DateTime.now()));
    expect(closed, isTrue);
    expect(closedWith, isTrue);
    expect(find.text(l.transactionFormCreateSuccessOnline), findsOneWidget);
  });

  testWidgets('an empty name sends the default name; offline saves locally',
      (tester) async {
    await open(tester, online: false);

    await tester.enterText(field('transactionFormAmount'), '12');
    await tester.tap(find.byKey(const ValueKey('transactionFormAdd')));
    await tester.pumpAndSettle();

    final call = transactions.calls.single;
    expect(call['name'], 'SureApp');
    expect(call['nature'], 'expense');
    expect(call['categoryId'], isNull);
    expect(closedWith, isTrue);
    expect(find.text(l.transactionFormCreateSuccessOffline), findsOneWidget);
  });

  testWidgets('a chosen category can be cleared', (tester) async {
    await open(tester);

    await tester.tap(find.byKey(const ValueKey('transactionFormCategory')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category-cat_rent')));
    await tester.pumpAndSettle();
    expect(find.text('Rent'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('transactionFormClearCategory')));
    await tester.pump();
    expect(find.text('Rent'), findsNothing);
    expect(find.text(l.transactionFormNoCategory), findsOneWidget);
  });

  testWidgets('Cancel closes with no result', (tester) async {
    await open(tester);
    await tester.tap(find.text(l.dsCancel));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(closedWith, isNull);
    expect(find.byType(TransactionFormScreen), findsNothing);
  });

  testWidgets('fits a 320 px screen with a category chosen', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('transactionFormCategory')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category-cat_food')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
