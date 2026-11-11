import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/theme/sure_tokens.dart';
import 'package:sure_mobile/utils/net_worth_history.dart';
import 'package:sure_mobile/widgets/balance_history_chart.dart';
import 'package:sure_mobile/widgets/money_text.dart';
import 'package:sure_mobile/widgets/net_worth_card.dart';
import 'package:sure_mobile/widgets/sure_chip.dart';

import '../support/ds_harness.dart';

NetWorthHistory _history(List<int> cents) => NetWorthHistory(
      points: [
        for (var i = 0; i < cents.length; i++)
          NetWorthPoint(DateTime(2026, 10, 1 + i), cents[i]),
      ],
      otherCurrencies: const [],
    );

String _plain(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).textSpan!.toPlainText();

void main() {
  for (final brightness in brightnesses) {
    final tokens =
        brightness == Brightness.dark ? SureTokens.dark : SureTokens.light;

    testWidgets('a rise shows the change in success with the range '
        '(${brightness.name})', (tester) async {
      await pumpDs(
        tester,
        NetWorthCard(
          netWorthFormatted: r'$93,000',
          history: _history([1000000, 1100000]),
          historyCurrency: 'USD',
          onRangeChanged: (_) {},
        ),
        brightness: brightness,
      );

      expect(find.text('Net worth'), findsOneWidget);
      final hero = tester.widget<MoneyText>(find.byKey(const ValueKey('netWorthHero')));
      expect(hero.text, r'$93,000');
      expect(hero.color, tokens.textPrimary);
      expect(_plain(tester, const ValueKey('netWorthChange')),
          r'+$1,000.00 (10.0%)  3M');
      final span = tester
          .widget<Text>(find.byKey(const ValueKey('netWorthChange')))
          .textSpan as TextSpan;
      expect(span.children!.first.style!.color, tokens.success);
      expect(find.byKey(const ValueKey('netWorthSparkline')), findsOneWidget);
    });

    testWidgets('a fall shows the change in destructive (${brightness.name})',
        (tester) async {
      await pumpDs(
        tester,
        NetWorthCard(
          netWorthFormatted: r'$90,000',
          history: _history([1000000, 900000]),
          historyCurrency: 'USD',
          range: AccountChartRange.month,
        ),
        brightness: brightness,
      );
      expect(_plain(tester, const ValueKey('netWorthChange')),
          r'-$1,000.00 (10.0%)  1M');
      final span = tester
          .widget<Text>(find.byKey(const ValueKey('netWorthChange')))
          .textSpan as TextSpan;
      expect(span.children!.first.style!.color, tokens.destructive);
    });
  }

  testWidgets('chips pick a range; the selected one does not refire',
      (tester) async {
    final picked = <AccountChartRange>[];
    await pumpDs(
      tester,
      NetWorthCard(
        netWorthFormatted: r'$1',
        onRangeChanged: picked.add,
      ),
    );
    expect(find.byType(SureChip), findsNWidgets(4));
    await tester.tap(find.widgetWithText(SureChip, '1Y'));
    await tester.tap(find.widgetWithText(SureChip, '3M'));
    expect(picked, [AccountChartRange.year]);
  });

  testWidgets('without history: no change line, trend line or chips',
      (tester) async {
    await pumpDs(tester, const NetWorthCard(netWorthFormatted: r'$1'));
    expect(find.byKey(const ValueKey('netWorthChange')), findsNothing);
    expect(find.byKey(const ValueKey('netWorthSparkline')), findsNothing);
    expect(find.byType(SureChip), findsNothing);
  });

  testWidgets('stale and cached: Outdated badge, dimmed hero, updated label',
      (tester) async {
    await pumpDs(
      tester,
      const NetWorthCard(
        netWorthFormatted: r'$1',
        isStale: true,
        updatedLabel: 'Updated 2 hours ago',
      ),
    );
    expect(find.text('Outdated'), findsOneWidget);
    expect(find.text('Updated 2 hours ago'), findsOneWidget);
    final hero = tester.widget<MoneyText>(find.byKey(const ValueKey('netWorthHero')));
    expect(hero.color, SureTokens.light.textSubdued);
  });

  testWidgets('unknown net worth reads "--"; privacy masks the change',
      (tester) async {
    await pumpDs(
      tester,
      NetWorthCard(
        history: _history([100, 200]),
        historyCurrency: 'USD',
      ),
      privacyHidden: true,
    );
    expect(find.text('--'), findsOneWidget);
    expect(_plain(tester, const ValueKey('netWorthChange')),
        isNot(contains('1.00')));
  });
}
