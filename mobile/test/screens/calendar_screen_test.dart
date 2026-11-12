import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sure_mobile/models/transaction.dart';
import 'package:sure_mobile/providers/accounts_provider.dart';
import 'package:sure_mobile/providers/auth_provider.dart';
import 'package:sure_mobile/providers/transactions_provider.dart';
import 'package:sure_mobile/screens/calendar_screen.dart';
import 'package:sure_mobile/theme/sure_colors.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';

import '../support/home_fixtures.dart';
import '../support/l10n_harness.dart';

class _Transactions extends TransactionsProvider {
  _Transactions(this._all);

  final List<Transaction> _all;
  String? accountId;

  @override
  List<Transaction> get transactions =>
      _all.where((t) => t.accountId == accountId).toList();

  @override
  bool get isLoading => false;

  @override
  Future<void> fetchTransactions({
    required String accessToken,
    String? accountId,
    bool forceSync = false,
  }) async =>
      this.accountId = accountId;
}

Transaction _txn(String account, String name, String date, String amount) =>
    Transaction(
      id: '$account-$name',
      accountId: account,
      name: name,
      date: date,
      amount: amount,
      currency: 'USD',
      nature: 'expense',
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final accounts = [
    homeAccount('checking', name: 'Checking', balance: r'$1,000.00'),
    homeAccount('savings', name: 'Savings', balance: r'$5,000.00'),
  ];

  Future<_Transactions> pump(WidgetTester tester) async {
    final transactions = _Transactions([
      _txn('checking', 'Coffee', '2026-11-05', r'$40.00'),
      _txn('checking', 'Salary', '2026-11-03', r'-$100.00'),
      _txn('savings', 'Interest', '2026-11-07', r'-$2.00'),
    ]);
    await pumpLocalized(
      tester,
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(create: (_) => FakeAuth()),
          ChangeNotifierProvider<AccountsProvider>(
              create: (_) => FakeAccountsProvider(accounts: accounts)),
          ChangeNotifierProvider<TransactionsProvider>.value(
              value: transactions),
        ],
        child: CalendarScreen(now: () => DateTime(2026, 11, 11)),
      ),
    );
    return transactions;
  }

  testWidgets('month grid tints days by direction; total is MoneyText',
      (tester) async {
    await pump(tester);

    expect(find.text('November 2026'), findsOneWidget);
    expect(find.text('Checking'), findsOneWidget);
    final total =
        tester.widget<MoneyText>(find.byKey(const ValueKey('calendarMonthTotal')));
    expect(total.text, r'+$60');
    expect(total.trend, MoneyTrend.inflow);

    final palette = SureColors.of(tester.element(find.text('Checking'))).palette;
    Color? fill(int day) => (tester
            .widget<Container>(find.descendant(
                of: find.byKey(ValueKey('calendarDay-$day')),
                matching: find.byType(Container)))
            .decoration as BoxDecoration?)
        ?.color;
    expect(fill(5), palette.destructive.withValues(alpha: 0.14));
    expect(fill(3), palette.success.withValues(alpha: 0.14));
    expect(fill(4), isNull);
    expect(find.byType(SegmentedButton<String>), findsNothing);
    expect(find.byType(SureSegmentedControl<String>), findsOneWidget);
  });

  testWidgets('second tap on a day opens its transactions in a sheet',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('calendarDay-5')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('calendarDay-5')));
    await tester.pumpAndSettle();

    expect(find.byType(SureSheet), findsOneWidget);
    expect(find.text('Nov 5, 2026'), findsOneWidget);
    expect(find.text('Coffee'), findsOneWidget);
    expect(find.byType(SureTransactionRow), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('the account picker is a sheet and reloads the calendar',
      (tester) async {
    final transactions = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('calendarAccountRow')));
    await tester.pumpAndSettle();
    expect(find.byType(SureSheet), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('calendarAccount-savings')));
    await tester.pumpAndSettle();
    expect(transactions.accountId, 'savings');
    expect(find.text('Savings'), findsOneWidget);
    expect(
        tester
            .widget<MoneyText>(
                find.byKey(const ValueKey('calendarMonthTotal')))
            .text,
        r'+$2');
  });

  testWidgets('no accounts of the chosen type shows an empty state',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('Liabilities'));
    await tester.pumpAndSettle();
    expect(find.text('No accounts of this type'), findsOneWidget);
    expect(find.byType(SureEmptyState), findsOneWidget);
  });
}
