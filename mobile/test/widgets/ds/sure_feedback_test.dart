import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/theme/sure_tokens.dart';
import 'package:sure_mobile/widgets/ds/sure_banner.dart';
import 'package:sure_mobile/widgets/ds/sure_empty_state.dart';
import 'package:sure_mobile/widgets/ds/sure_search_field.dart';
import 'package:sure_mobile/widgets/sure_icon.dart';

import '../../support/ds_harness.dart';

void main() {
  for (final brightness in brightnesses) {
    final tokens =
        brightness == Brightness.dark ? SureTokens.dark : SureTokens.light;

    testWidgets(
        'empty state: icon circle, title, body, button, link '
        '(${brightness.name}, 320 px)', (tester) async {
      var primary = 0;
      var secondary = 0;
      await pumpDs(
        tester,
        SureEmptyState(
          icon: SureIcons.landmark,
          title: 'No accounts yet ' * 4,
          body: 'Connect a bank on the web, or add a manual account. ' * 3,
          primaryLabel: 'Connect on the web',
          onPrimary: () => primary++,
          secondaryLabel: 'Add a manual account',
          onSecondary: () => secondary++,
        ),
        brightness: brightness,
        width: 320,
        scroll: true,
      );
      expect(tester.takeException(), isNull);
      final icon = tester.widget<SureIcon>(find.byType(SureIcon));
      expect(icon.name, SureIcons.landmark);
      expect(icon.color, tokens.textSecondary);
      final circle = tester.widget<Container>(find
          .ancestor(of: find.byType(SureIcon), matching: find.byType(Container))
          .first);
      expect((circle.decoration as BoxDecoration).color, tokens.surfaceInset);
      expect(tester.getSize(find.byWidget(circle)), const Size.square(52));

      await tester.tap(find.text('Connect on the web'));
      await tester.tap(find.text('Add a manual account'));
      expect((primary, secondary), (1, 1));
    });

    testWidgets(
        'banner: 15% warning fill, one ellipsized line '
        '(${brightness.name}, 320 px)', (tester) async {
      await pumpDs(
        tester,
        SureBanner(message: 'Offline · showing data from 2h ago ' * 4),
        brightness: brightness,
        width: 320,
      );
      expect(tester.takeException(), isNull);
      final box = tester.widget<Container>(find
          .descendant(
              of: find.byType(SureBanner), matching: find.byType(Container))
          .first);
      expect((box.decoration as BoxDecoration).color,
          tokens.warning.withValues(alpha: 0.15));
      final text = tester.widget<Text>(find.textContaining('Offline'));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(
          tester.widget<SureIcon>(find.byType(SureIcon)).color, tokens.warning);
    });

    testWidgets(
        'search field: inset fill, search icon, clear button '
        '(${brightness.name})', (tester) async {
      final changes = <String>[];
      await pumpDs(
        tester,
        SureSearchField(
          hintText: 'Search transactions',
          onChanged: changes.add,
          clearSemanticLabel: 'Clear search',
        ),
        brightness: brightness,
        width: 320,
      );
      final box = tester.widget<Container>(find
          .descendant(
              of: find.byType(SureSearchField),
              matching: find.byType(Container))
          .first);
      expect((box.decoration as BoxDecoration).color, tokens.surfaceInset);
      expect(tester.widget<SureIcon>(find.byType(SureIcon)).name,
          SureIcons.search);
      expect(find.bySemanticsLabel('Clear search'), findsNothing);

      await tester.enterText(find.byType(TextField), 'starbuck');
      await tester.pump();
      expect(changes, ['starbuck']);
      expect(find.bySemanticsLabel('Clear search'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Clear search'));
      await tester.pump();
      expect(changes, ['starbuck', '']);
      expect(find.text('starbuck'), findsNothing);
    });
  }

  testWidgets('empty state without callbacks shows no button or link',
      (tester) async {
    await pumpDs(
      tester,
      const SureEmptyState(
        icon: SureIcons.search,
        title: 'No matches',
        primaryLabel: 'Do it',
        secondaryLabel: 'Clear filters',
      ),
    );
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('banner action fires', (tester) async {
    var taps = 0;
    await pumpDs(
      tester,
      SureBanner(
        icon: SureIcons.cloudOff,
        message: 'Offline',
        actionLabel: 'Retry',
        onAction: () => taps++,
      ),
    );
    await tester.tap(find.text('Retry'));
    expect(taps, 1);
  });
}
