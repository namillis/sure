import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/providers/accounts_provider.dart';
import 'package:sure_mobile/providers/privacy_provider.dart';
import 'package:sure_mobile/screens/account_group_screen.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/account_card.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';

import '../support/home_fixtures.dart';

void main() {
  group('AccountGroup.build', () {
    test('orders types like the web and totals per currency', () {
      final groups = AccountGroup.build([
        homeAccount('loan', type: 'loan', classification: 'liability', balance: r'$5.00'),
        homeAccount('card1', type: 'credit_card', classification: 'liability', balance: r'$20.00'),
        homeAccount('card2', type: 'credit_card', classification: 'liability', balance: r'$0.00'),
        homeAccount('cash', balance: r'$100.00'),
        homeAccount('uk', currency: 'GBP', balance: '£50.00'),
        homeAccount('odd', type: 'mystery', balance: r'$1.00'),
        homeAccount('none', classification: 'other', balance: r'$9.00'),
      ], mainCurrency: 'USD');

      expect(groups.map((g) => g.accountType),
          ['depository', 'credit_card', 'loan', 'mystery']);
      final cash = groups.first;
      expect(cash.primaryCurrency, 'USD');
      expect(cash.primaryTotal, 100);
      expect(cash.otherCurrencies, ['GBP']);
      expect(cash.totals['GBP'], 50);

      final cards = groups[1];
      expect(cards.primaryTotal, -20);
      expect(cards.emptyCount, 1);
      expect(cards.accounts.last.id, 'card2', reason: 'empty accounts last');
      expect(cards.isLiability, isTrue);
    });

    test('a group with no main-currency account totals its own currency', () {
      final groups = AccountGroup.build([
        homeAccount('b1', type: 'crypto', currency: 'BTC', balance: '0.5'),
        homeAccount('b2', type: 'crypto', currency: 'BTC', balance: '0.25'),
        homeAccount('e1', type: 'crypto', currency: 'ETH', balance: '2'),
      ], mainCurrency: 'USD');
      expect(groups.single.primaryCurrency, 'BTC');
      expect(groups.single.primaryTotal, 0.75);
      expect(groups.single.otherCurrencies, ['ETH']);
    });
  });

  Future<void> pump(
    WidgetTester tester, {
    double width = 390,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PrivacyProvider>(
              create: (_) => PrivacyProvider(initialHidden: false)),
          ChangeNotifierProvider<AccountsProvider>(
            create: (_) => FakeAccountsProvider(accounts: [
              homeAccount('a', name: 'Checking', balance: r'$10.00'),
              homeAccount('b', name: 'Dormant one', balance: r'$0.00'),
              homeAccount('c', name: 'Dormant two', balance: r'$0.00'),
              homeAccount('d', name: 'Card', type: 'credit_card',
                  classification: 'liability', balance: r'$1.00'),
            ]),
          ),
        ],
        child: MaterialApp(
          theme:
              brightness == Brightness.dark ? SureTheme.dark : SureTheme.light,
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const AccountGroupScreen(accountType: 'depository'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('large title is the type; empty accounts are collapsed',
      (tester) async {
    await pump(tester);
    expect(find.text('Cash'), findsWidgets);
    expect(find.byType(AccountCard), findsOneWidget);
    expect(find.text('Checking'), findsOneWidget);
    expect(find.text('Card'), findsNothing, reason: 'other types');
    expect(find.text('2 empty accounts · Show'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('emptyAccountsToggle')));
    await tester.pumpAndSettle();
    expect(find.byType(AccountCard), findsNWidgets(3));
    expect(find.text('2 empty accounts · Hide'), findsOneWidget);
  });

  testWidgets('a type with no accounts shows an empty state', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PrivacyProvider>(
              create: (_) => PrivacyProvider(initialHidden: false)),
          ChangeNotifierProvider<AccountsProvider>(
              create: (_) => FakeAccountsProvider()),
        ],
        child: MaterialApp(
          theme: SureTheme.light,
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const AccountGroupScreen(accountType: 'loan'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SureEmptyState), findsOneWidget);
    expect(find.text('No accounts of this type'), findsOneWidget);
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('fits 320 px (${brightness.name})', (tester) async {
      await pump(tester, width: 320, brightness: brightness);
      expect(tester.takeException(), isNull);
    });
  }
}
