import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/theme/sure_tokens.dart';
import 'package:sure_mobile/widgets/account_card.dart';
import 'package:sure_mobile/widgets/money_text.dart';

import '../support/ds_harness.dart';
import '../support/home_fixtures.dart';

void main() {
  for (final brightness in brightnesses) {
    final tokens =
        brightness == Brightness.dark ? SureTokens.dark : SureTokens.light;

    testWidgets('liability balance is negative in destructive '
        '(${brightness.name})', (tester) async {
      await pumpDs(
        tester,
        AccountCard(
          account: homeAccount('1',
              name: 'Sapphire',
              type: 'credit_card',
              classification: 'liability',
              balance: r'$100.00'),
        ),
        brightness: brightness,
      );
      final balance = tester.widget<MoneyText>(find.byType(MoneyText));
      expect(balance.text, r'-$100.00');
      expect(balance.color, tokens.destructive);
    });

    testWidgets('asset balance is textPrimary with no currency code '
        '(${brightness.name})', (tester) async {
      await pumpDs(
        tester,
        AccountCard(
          account: homeAccount('1',
              name: 'Checking', balance: r'$100.00', institution: 'Chase'),
        ),
        brightness: brightness,
      );
      final balance = tester.widget<MoneyText>(find.byType(MoneyText));
      expect(balance.text, r'$100.00');
      expect(balance.color, tokens.textPrimary);
      expect(find.text('Chase'), findsOneWidget);
      expect(find.text('USD'), findsNothing);
    });
  }

  testWidgets('falls back to minor units and masks in privacy mode',
      (tester) async {
    await pumpDs(
      tester,
      AccountCard(
        account: homeAccount('1', balance: '', cents: 12345),
      ),
      privacyHidden: true,
    );
    expect(tester.widget<MoneyText>(find.byType(MoneyText)).text, r'$••••');
  });

  testWidgets('swiping left reveals Add, which calls onSwipe', (tester) async {
    var swiped = 0;
    await pumpDs(
      tester,
      AccountCard(
        account: homeAccount('1', name: 'Checking', balance: r'$1.00'),
        onSwipe: () => swiped++,
      ),
    );
    await tester.drag(find.text('Checking'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(swiped, 1);
  });

  testWidgets('a long name ellipsizes at 320 px', (tester) async {
    await pumpDs(
      tester,
      AccountCard(
        account: homeAccount('1',
            name: 'A very long account name that will never fit on one line',
            institution: 'An institution with an equally long name',
            balance: r'$1,234,567.89'),
      ),
      width: 320,
    );
    expect(tester.takeException(), isNull);
  });
}
