import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/theme/sure_tokens.dart';
import 'package:sure_mobile/widgets/money_text.dart';

void main() {
  group('SureMoney.trendForAmount', () {
    test('null amount is neutral', () {
      expect(SureMoney.trendForAmount(null), MoneyTrend.neutral);
    });

    test('positive and zero are inflow, negative is outflow', () {
      expect(SureMoney.trendForAmount(12.5), MoneyTrend.inflow);
      expect(SureMoney.trendForAmount(0), MoneyTrend.inflow);
      expect(SureMoney.trendForAmount(-3), MoneyTrend.outflow);
    });
  });

  Future<BuildContext> pumpContext(WidgetTester tester, ThemeData theme) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return captured;
  }

  group('SureMoney.color resolves design-system tokens', () {
    testWidgets('light theme maps trends to success/destructive/subdued',
        (tester) async {
      final context = await pumpContext(tester, SureTheme.light);
      expect(SureMoney.color(context, MoneyTrend.inflow),
          SureTokens.light.success);
      expect(SureMoney.color(context, MoneyTrend.outflow),
          SureTokens.light.destructive);
      expect(SureMoney.color(context, MoneyTrend.neutral),
          SureTokens.light.textSubdued);
    });

    testWidgets('dark theme resolves the dark palette', (tester) async {
      final context = await pumpContext(tester, SureTheme.dark);
      expect(
          SureMoney.color(context, MoneyTrend.inflow), SureTokens.dark.success);
      expect(SureMoney.color(context, MoneyTrend.outflow),
          SureTokens.dark.destructive);
    });
  });

  group('MoneyText', () {
    testWidgets('applies semantic color and tabular figures', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: SureTheme.light,
          home: const Scaffold(
            body: MoneyText('+\$10.00', trend: MoneyTrend.inflow),
          ),
        ),
      );

      final text = tester.widget<Text>(find.text('+\$10.00'));
      expect(text.style?.color, SureTokens.light.success);
      expect(text.style?.fontFeatures,
          contains(const FontFeature.tabularFigures()));
    });
  });

  group('Geist Mono', () {
    for (final theme in [SureTheme.light, SureTheme.dark]) {
      testWidgets(
          'MoneyText renders in Geist Mono with tabular figures '
          '(${theme.brightness.name})', (tester) async {
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: MoneyText(r'-$1,204.11',
                trend: MoneyTrend.outflow, style: TextStyle(fontSize: 32)),
          ),
        ));
        final text = tester.widget<Text>(find.text(r'-$1,204.11'));
        expect(text.style?.fontFamily, SureTokens.fontMono);
        expect(text.style?.fontFeatures,
            contains(const FontFeature.tabularFigures()));
        expect(text.style?.fontSize, 32);
        expect(text.style?.fontWeight, FontWeight.w600);
      });
    }

    testWidgets('an explicit color overrides the trend color', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: SureTheme.light,
        home: Scaffold(
          body: MoneyText(r'$5.00',
              trend: MoneyTrend.outflow, color: SureTokens.light.textPrimary),
        ),
      ));
      expect(tester.widget<Text>(find.text(r'$5.00')).style?.color,
          SureTokens.light.textPrimary);
    });

    test('SureMoney.tabular applies the mono family too', () {
      final style = SureMoney.tabular(const TextStyle(fontSize: 13));
      expect(style.fontFamily, SureTokens.fontMono);
      expect(style.fontSize, 13);
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
    });

    test('Geist Mono is bundled at 400, 500 and 600', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('family: Geist Mono'));
      for (final file in [
        'GeistMono-Regular.ttf',
        'GeistMono-Medium.ttf',
        'GeistMono-SemiBold.ttf',
      ]) {
        expect(pubspec, contains('assets/fonts/$file'));
        expect(File('assets/fonts/$file').existsSync(), isTrue, reason: file);
      }
    });
  });
}
