import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sure_mobile/models/transaction.dart';
import 'package:sure_mobile/providers/accounts_provider.dart';
import 'package:sure_mobile/providers/auth_provider.dart';
import 'package:sure_mobile/providers/transactions_provider.dart';
import 'package:sure_mobile/screens/recent_transactions_screen.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';

import '../support/home_fixtures.dart';
import '../support/l10n_harness.dart';

class _Transactions extends TransactionsProvider {
  _Transactions(this._items, {this.failure});

  final List<Transaction> _items;
  final String? failure;
  final fetches = <bool>[];

  @override
  List<Transaction> get transactions => _items;

  @override
  bool get isLoading => false;

  @override
  String? get error => failure;

  @override
  Future<void> fetchTransactions({
    required String accessToken,
    String? accountId,
    bool forceSync = false,
  }) async =>
      fetches.add(forceSync);
}

Transaction _txn(int i, String date) => Transaction(
      id: 't$i',
      accountId: 'checking',
      name: 'Txn $i',
      date: date,
      amount: r'$10.00',
      currency: 'USD',
      nature: 'expense',
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_Transactions> pump(WidgetTester tester, _Transactions provider) async {
    await pumpLocalized(
      tester,
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(create: (_) => FakeAuth()),
          ChangeNotifierProvider<AccountsProvider>(
            create: (_) => FakeAccountsProvider(accounts: [
              homeAccount('checking', name: 'Checking', balance: r'$1.00'),
            ]),
          ),
          ChangeNotifierProvider<TransactionsProvider>.value(value: provider),
        ],
        child: const RecentTransactionsScreen(),
      ),
    );
    return provider;
  }

  testWidgets('rows are grouped by day, newest first', (tester) async {
    await pump(
      tester,
      _Transactions([
        _txn(1, '2026-03-01'),
        _txn(2, '2026-03-04'),
        _txn(3, '2026-03-04'),
      ]),
    );

    expect(find.byType(SureTransactionRow), findsNWidgets(3));
    expect(find.byType(SureDayHeader), findsNWidgets(2));
    expect(find.byType(SurePanel), findsNWidgets(2));
    expect(find.byType(ListTile), findsNothing);
    expect(tester.getTopLeft(find.text('Txn 2')).dy,
        lessThan(tester.getTopLeft(find.text('Txn 1')).dy));
  });

  testWidgets('limit chips cap the list', (tester) async {
    await pump(
      tester,
      _Transactions([
        for (var i = 0; i < 25; i++)
          _txn(i, '2026-03-${(i + 1).toString().padLeft(2, '0')}'),
      ]),
    );
    final chip20 = find.byKey(const ValueKey('recentLimit-20'));
    expect(tester.widget<SureChip>(chip20).selected, isTrue);

    await tester.tap(find.byKey(const ValueKey('recentLimit-10')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<SureChip>(find.byKey(const ValueKey('recentLimit-10')))
            .selected,
        isTrue);
    expect(find.byType(SureTransactionRow, skipOffstage: false),
        findsNWidgets(10));
  });

  testWidgets('empty state', (tester) async {
    await pump(tester, _Transactions(const []));
    expect(find.text('No Transactions'), findsOneWidget);
    expect(find.byType(SureEmptyState), findsOneWidget);
  });

  testWidgets('error state retries with a sync', (tester) async {
    final provider =
        await pump(tester, _Transactions(const [], failure: 'offline'));
    expect(find.text("Couldn't load transactions"), findsOneWidget);
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();
    expect(provider.fetches, [false, true]);
  });

  test('byDay groups consecutive rows on the same day', () {
    final days = RecentTransactionsScreen.byDay([
      _txn(1, '2026-03-04'),
      _txn(2, '2026-03-04T10:00:00'),
      _txn(3, '2026-03-01'),
    ]);
    expect(days.map((d) => d.rows.length), [2, 1]);
  });
}
