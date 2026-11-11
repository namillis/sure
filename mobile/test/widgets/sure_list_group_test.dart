import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/theme/sure_colors.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/theme/sure_tokens.dart';
import 'package:sure_mobile/widgets/ds/sure_panel.dart';
import 'package:sure_mobile/widgets/sure_icon.dart';
import 'package:sure_mobile/widgets/sure_list_group.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child,
      {Brightness brightness = Brightness.light}) {
    return tester.pumpWidget(
      MaterialApp(
        theme:
            brightness == Brightness.light ? SureTheme.light : SureTheme.dark,
        home: Scaffold(body: child),
      ),
    );
  }

  // Brightness-aware by contract — assert the chrome resolves the right palette
  // in both themes so a token regression in either mode is caught.
  for (final (brightness, tokens) in [
    (Brightness.light, SureTokens.light),
    (Brightness.dark, SureTokens.dark),
  ]) {
    testWidgets(
        'paints the group as a flat hairline panel (${brightness.name})',
        (tester) async {
      await pump(
        tester,
        const SureListGroup(children: [SureListRow(title: 'Only row')]),
        brightness: brightness,
      );

      expect(find.byType(SurePanel), findsOneWidget);
      final fill = tester.widget<ColoredBox>(find
          .descendant(
              of: find.byType(SurePanel), matching: find.byType(ColoredBox))
          .first);
      expect(fill.color, tokens.container);
      final outline = tester
          .widget<DecoratedBox>(find
              .descendant(
                  of: find.byType(SurePanel),
                  matching: find.byType(DecoratedBox))
              .first)
          .decoration as BoxDecoration;
      expect((outline.border as Border).top.color, SureColors(tokens).hairline);
      expect(outline.borderRadius, BorderRadius.circular(SureTokens.radiusLg));
      expect(outline.boxShadow, isNull);
    });

    testWidgets(
        'inserts hairline interior dividers but not at the edges (${brightness.name})',
        (tester) async {
      await pump(
        tester,
        const SureListGroup(children: [
          SureListRow(title: 'One'),
          SureListRow(title: 'Two'),
          SureListRow(title: 'Three'),
        ]),
        brightness: brightness,
      );

      // Three rows => exactly two interior dividers.
      expect(find.byType(SureHairline), findsNWidgets(2));
    });
  }

  testWidgets('renders a sentence-case header above the group', (tester) async {
    await pump(
      tester,
      const SureListGroup(
        header: 'Tools',
        children: [SureListRow(title: 'Calendar')],
      ),
    );
    expect(find.text('Tools'), findsOneWidget);
  });

  testWidgets('value and chevron show together', (tester) async {
    await pump(
      tester,
      const SureListGroup(children: [
        SureListRow(title: 'Category', value: 'Groceries', showChevron: true),
      ]),
    );
    expect(find.text('Groceries'), findsOneWidget);
    expect(tester.widget<SureIcon>(find.byType(SureIcon)).name,
        SureIcons.chevronRight);
  });

  testWidgets('one-line rows are 44 tall, two-line rows at least 52',
      (tester) async {
    await pump(
      tester,
      const SureListGroup(children: [
        SureListRow(title: 'One line'),
        SureListRow(title: 'Two', subtitle: 'lines'),
      ]),
    );
    expect(tester.getSize(find.byType(SureListRow).first).height, 44);
    expect(tester.getSize(find.byType(SureListRow).last).height,
        greaterThanOrEqualTo(52));
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'long title, subtitle and value ellipsize at 320 px (${brightness.name})',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(
        tester,
        SureListGroup(children: [
          SureListRow(
            leading: const SizedBox.square(dimension: 28),
            title: 'A very long title ' * 6,
            subtitle: 'A very long subtitle ' * 6,
            value: 'A long value ' * 4,
            showChevron: true,
          ),
        ]),
        brightness: brightness,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final (brightness, tokens) in [
    (Brightness.light, SureTokens.light),
    (Brightness.dark, SureTokens.dark),
  ]) {
    testWidgets(
        'row renders title and subtitle with tokenized colors (${brightness.name})',
        (tester) async {
      await pump(
        tester,
        const SureListGroup(
          children: [SureListRow(title: 'Calendar', subtitle: 'Monthly view')],
        ),
        brightness: brightness,
      );
      final title = tester.widget<Text>(find.text('Calendar'));
      final subtitle = tester.widget<Text>(find.text('Monthly view'));
      expect(title.style?.color, tokens.textPrimary);
      expect(subtitle.style?.color, tokens.textSecondary);
    });

    testWidgets(
        'destructive row paints the title in the destructive token (${brightness.name})',
        (tester) async {
      await pump(
        tester,
        const SureListGroup(
          children: [SureListRow(title: 'Delete account', destructive: true)],
        ),
        brightness: brightness,
      );
      final title = tester.widget<Text>(find.text('Delete account'));
      expect(title.style?.color, tokens.destructive);
    });
  }

  testWidgets(
      'showChevron renders the DS chevron, suppressed by explicit trailing',
      (tester) async {
    await pump(
      tester,
      const SureListGroup(
          children: [SureListRow(title: 'Go', showChevron: true)]),
    );
    final chevron = tester.widget<SureIcon>(find.byType(SureIcon));
    expect(chevron.name, SureIcons.chevronRight);

    await pump(
      tester,
      const SureListGroup(children: [
        SureListRow(
          title: 'Go',
          showChevron: true,
          trailing: Text('value'),
        ),
      ]),
    );
    expect(find.byType(SureIcon), findsNothing);
    expect(find.text('value'), findsOneWidget);
  });

  testWidgets('onTap fires and the tappable row uses an InkWell',
      (tester) async {
    var taps = 0;
    await pump(
      tester,
      SureListGroup(
        children: [SureListRow(title: 'Tap me', onTap: () => taps++)],
      ),
    );
    expect(find.byType(InkWell), findsOneWidget);
    await tester.tap(find.text('Tap me'));
    expect(taps, 1);
  });

  testWidgets('a row without onTap is non-interactive (no InkWell)',
      (tester) async {
    await pump(
      tester,
      const SureListGroup(children: [SureListRow(title: 'Static')]),
    );
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('a tappable row exposes button semantics (ListTile parity)',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      SureListGroup(children: [SureListRow(title: 'Go', onTap: () {})]),
    );
    final node = tester.getSemantics(find.text('Go'));
    expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(node.hasFlag(SemanticsFlag.isEnabled), isTrue);
    handle.dispose();
  });

  testWidgets('an empty group builds no chrome', (tester) async {
    await pump(tester, const SureListGroup(children: []));
    // No panel and no dividers — it collapses rather than painting an empty
    // bordered box.
    expect(find.byType(SurePanel), findsNothing);
    expect(find.byType(SureHairline), findsNothing);
  });
}
