import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/theme/sure_colors.dart';
import 'package:sure_mobile/theme/sure_tokens.dart';
import 'package:sure_mobile/widgets/ds/sure_panel.dart';
import 'package:sure_mobile/widgets/ds/sure_section_header.dart';
import 'package:sure_mobile/widgets/sure_icon.dart';
import 'package:sure_mobile/widgets/sure_list_group.dart';

import '../../support/ds_harness.dart';

void main() {
  for (final brightness in brightnesses) {
    final tokens =
        brightness == Brightness.dark ? SureTokens.dark : SureTokens.light;

    testWidgets(
        'panel: container fill, hairline outline, no shadow '
        '(${brightness.name})', (tester) async {
      await pumpDs(tester, const SurePanel(child: Text('Body')),
          brightness: brightness);
      final fill = tester.widget<ColoredBox>(find
          .descendant(
              of: find.byType(SurePanel), matching: find.byType(ColoredBox))
          .first);
      expect(fill.color, tokens.container);
      final box = tester.widget<DecoratedBox>(find
          .descendant(
              of: find.byType(SurePanel), matching: find.byType(DecoratedBox))
          .first);
      final deco = box.decoration as BoxDecoration;
      expect(box.position, DecorationPosition.foreground);
      expect((deco.border as Border).top.color, SureColors(tokens).hairline);
      expect((deco.border as Border).top.width, 1);
      expect(deco.boxShadow, isNull);
      expect(find.byType(ClipRRect), findsOneWidget);
    });

    testWidgets('rows panel: hairlines between rows only (${brightness.name})',
        (tester) async {
      await pumpDs(
        tester,
        const SurePanel.rows(
          dividerIndent: SurePanel.iconRowDividerIndent,
          children: [
            SureListRow(title: 'A'),
            SureListRow(title: 'B'),
            SureListRow(title: 'C'),
          ],
        ),
        brightness: brightness,
      );
      expect(find.byType(SureHairline), findsNWidgets(2));
      final line = tester.widget<SureHairline>(find.byType(SureHairline).first);
      expect(line.indent, SurePanel.iconRowDividerIndent);
      final color = tester.widget<ColoredBox>(find
          .descendant(
              of: find.byType(SureHairline).first,
              matching: find.byType(ColoredBox))
          .first);
      expect(color.color, SureColors(tokens).hairline);
      expect(tester.getSize(find.byType(SureHairline).first).height, 1);
    });

    testWidgets(
        'section header: sentence case, link action, no overflow at '
        '320 px (${brightness.name})', (tester) async {
      var taps = 0;
      await pumpDs(
        tester,
        SureSectionHeader(
          label: 'A very long section label that must ellipsize ' * 3,
          actionLabel: 'See all',
          onAction: () => taps++,
        ),
        brightness: brightness,
        width: 320,
      );
      expect(tester.takeException(), isNull);
      final link = tester.widget<Text>(find.text('See all'));
      expect(link.style?.color, tokens.link);
      await tester.tap(find.text('See all'));
      expect(taps, 1);
    });
  }

  testWidgets('empty rows panel renders nothing', (tester) async {
    await pumpDs(tester, const SurePanel.rows(children: []));
    expect(
        find.descendant(
            of: find.byType(SurePanel), matching: find.byType(ColoredBox)),
        findsNothing);
  });

  testWidgets('a tappable panel fires onTap', (tester) async {
    var taps = 0;
    await pumpDs(
        tester, SurePanel(onTap: () => taps++, child: const Text('Insight')));
    await tester.tap(find.text('Insight'));
    expect(taps, 1);
  });

  testWidgets('section header label is shown as given', (tester) async {
    await pumpDs(tester, const SureSectionHeader(label: 'Recent'));
    expect(find.text('Recent'), findsOneWidget);
    final text = tester.widget<Text>(find.text('Recent'));
    expect(text.style?.fontSize, 13);
    expect(text.style?.fontWeight, FontWeight.w500);
    expect(text.style?.color, SureTokens.light.textSecondary);
  });

  testWidgets('section header icon action', (tester) async {
    var taps = 0;
    await pumpDs(
      tester,
      SureSectionHeader(
        label: 'Accounts',
        actionIcon: SureIcons.plus,
        actionSemanticLabel: 'Add account',
        onAction: () => taps++,
      ),
    );
    expect(tester.widget<SureIcon>(find.byType(SureIcon)).name, SureIcons.plus);
    await tester.tap(find.byType(SureIcon));
    expect(taps, 1);
    expect(find.bySemanticsLabel('Add account'), findsOneWidget);
  });
}
