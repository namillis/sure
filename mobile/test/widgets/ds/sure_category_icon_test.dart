import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/theme/sure_tokens.dart';
import 'package:sure_mobile/widgets/ds/sure_category_icon.dart';
import 'package:sure_mobile/widgets/sure_icon.dart';

import '../../support/ds_harness.dart';

void main() {
  BoxDecoration circleOf(WidgetTester tester) => tester
      .widget<DecoratedBox>(find
          .descendant(
              of: find.byType(SureCategoryIcon),
              matching: find.byType(DecoratedBox))
          .first)
      .decoration as BoxDecoration;

  for (final brightness in brightnesses) {
    final tokens =
        brightness == Brightness.dark ? SureTokens.dark : SureTokens.light;
    final alpha = brightness == Brightness.dark ? 0.18 : 0.14;

    testWidgets(
        'category: tinted circle, Lucide glyph in full color '
        '(${brightness.name})', (tester) async {
      await pumpDs(
        tester,
        const Center(
          child: SureCategoryIcon(
              name: 'Groceries', color: '#407706', icon: 'shopping-bag'),
        ),
        brightness: brightness,
      );
      const color = Color(0xFF407706);
      expect(circleOf(tester).color, color.withValues(alpha: alpha));
      expect(circleOf(tester).shape, BoxShape.circle);
      final glyph = tester.widget<SureIcon>(find.byType(SureIcon));
      expect(glyph.name, 'shopping-bag');
      expect(glyph.color, color);
      expect(tester.getSize(find.byType(SureCategoryIcon)),
          const Size.square(SureCategoryIcon.rowSize));
    });

    testWidgets('no category: neutral fill with a "?" (${brightness.name})',
        (tester) async {
      await pumpDs(tester, const Center(child: SureCategoryIcon()),
          brightness: brightness);
      expect(circleOf(tester).color, tokens.surfaceInset);
      final glyph = tester.widget<SureIcon>(find.byType(SureIcon));
      expect(glyph.name, SureIcons.circleQuestionMark);
      expect(glyph.color, tokens.textSecondary);
    });
  }

  testWidgets('transfer and split use neutral fills with their glyphs',
      (tester) async {
    await pumpDs(tester, const Center(child: SureCategoryIcon.transfer()));
    expect(tester.widget<SureIcon>(find.byType(SureIcon)).name,
        SureIcons.arrowLeftRight);
    expect(circleOf(tester).color, SureTokens.light.surfaceInset);

    await pumpDs(tester, const Center(child: SureCategoryIcon.split()));
    expect(
        tester.widget<SureIcon>(find.byType(SureIcon)).name, SureIcons.split);
  });

  testWidgets('unknown icon name falls back to the first letter',
      (tester) async {
    await pumpDs(
      tester,
      const Center(
          child: SureCategoryIcon(
              name: 'zebra fund', color: '#6366f1', icon: 'not-an-icon')),
    );
    expect(find.byType(SureIcon), findsNothing);
    final letter = tester.widget<Text>(find.text('Z'));
    expect(letter.style?.color, const Color(0xFF6366F1));
  });

  testWidgets('a missing icon also falls back to the first letter',
      (tester) async {
    await pumpDs(
        tester, const Center(child: SureCategoryIcon(name: 'Ölbryggning')));
    expect(find.text('Ö'), findsOneWidget);
  });

  testWidgets('legacy alias names render the canonical icon', (tester) async {
    await pumpDs(
      tester,
      const Center(
          child: SureCategoryIcon(
              name: 'Mortgage', color: '#b45309', icon: 'home')),
    );
    expect(tester.widget<SureIcon>(find.byType(SureIcon)).name, 'house');
  });

  testWidgets('dot size drops the glyph and fills with the solid color',
      (tester) async {
    await pumpDs(
      tester,
      const Center(
        child: SureCategoryIcon(
          name: 'Food',
          color: '#f97316',
          icon: 'utensils',
          size: SureCategoryIcon.dotSize,
        ),
      ),
    );
    expect(find.byType(SureIcon), findsNothing);
    expect(circleOf(tester).color, const Color(0xFFF97316));
  });

  testWidgets('hero size scales the glyph', (tester) async {
    await pumpDs(
      tester,
      const Center(
        child: SureCategoryIcon(
          name: 'Food',
          color: '#f97316',
          icon: 'utensils',
          size: SureCategoryIcon.heroSize,
        ),
      ),
    );
    expect(
        tester.getSize(find.byType(SureCategoryIcon)), const Size.square(48));
    expect(tester.widget<SureIcon>(find.byType(SureIcon)).size, 26);
  });

  group('SureIcons.forCategory', () {
    test('bundled names pass, aliases resolve, unknown is null', () {
      expect(SureIcons.forCategory('utensils'), 'utensils');
      expect(SureIcons.forCategory(' Coffee '), 'coffee');
      expect(SureIcons.forCategory('bar-chart-3'), 'chart-column');
      expect(SureIcons.forCategory('pie-chart'), 'chart-pie');
      expect(SureIcons.forCategory('train'), 'tram-front');
      expect(SureIcons.forCategory('nope'), isNull);
      expect(SureIcons.forCategory(''), isNull);
      expect(SureIcons.forCategory(null), isNull);
    });

    test('every server category icon is bundled as an SVG', () {
      for (final name in SureIcons.category) {
        expect(File('assets/icons/lucide/$name.svg').existsSync(), isTrue,
            reason: name);
      }
      for (final canonical in SureIcons.aliases.values) {
        expect(SureIcons.category, contains(canonical));
      }
    });

    test('the server icon lists are all covered', () {
      // Category.icon_codes, ICON_KEYWORDS values, the default categories
      // and the synthetic ones, read from the Rails model.
      final model = File('../app/models/category.rb');
      if (!model.existsSync()) return; // Mobile-only checkout.
      final source = model.readAsStringSync();
      final codes = RegExp(r'def icon_codes\s+%w\[([^\]]*)\]')
          .firstMatch(source)!
          .group(1)!
          .split(RegExp(r'\s+'))
          .where((s) => s.isNotEmpty);
      final quoted = [
        ...RegExp(r'=> "([a-z0-9-]+)"').allMatches(source),
        ...RegExp(r'lucide_icon: "([a-z0-9-]+)"').allMatches(source),
        ...RegExp(r'"#[0-9a-f]{6}", "([a-z0-9-]+)"').allMatches(source),
      ].map((m) => m.group(1)!);
      for (final name in {...codes, ...quoted}) {
        expect(SureIcons.forCategory(name), isNotNull, reason: name);
      }
    });
  });
}
