import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/theme/sure_colors.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/theme/sure_tokens.dart';
import 'package:sure_mobile/widgets/sure_chip.dart';
import 'package:sure_mobile/widgets/sure_icon.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Brightness brightness = Brightness.light,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme:
            brightness == Brightness.light ? SureTheme.light : SureTheme.dark,
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  Material materialOf(WidgetTester tester) => tester.widget<Material>(
        find
            .descendant(
                of: find.byType(SureChip), matching: find.byType(Material))
            .first,
      );

  // Brightness-aware by contract — assert both selection states resolve the
  // right tokens in light and dark.
  for (final (brightness, tokens) in [
    (Brightness.light, SureTokens.light),
    (Brightness.dark, SureTokens.dark),
  ]) {
    testWidgets(
      'selected chip fills with the neutral token (${brightness.name})',
      (tester) async {
        await pump(
          tester,
          const SureChip(label: 'USD', selected: true),
          brightness: brightness,
        );
        expect(materialOf(tester).color, tokens.buttonPrimary);
        final label = tester.widget<Text>(find.text('USD'));
        expect(label.style?.color, tokens.textInverse);
        expect(label.style?.fontWeight, FontWeight.w600);
        // Filled chip drops the border.
        expect(
          (materialOf(tester).shape as StadiumBorder).side,
          BorderSide.none,
        );
      },
    );

    testWidgets(
      'unselected chip is a hairline pill on the panel color (${brightness.name})',
      (tester) async {
        await pump(
          tester,
          const SureChip(label: 'USD'),
          brightness: brightness,
        );
        expect(materialOf(tester).color, tokens.container);
        expect(
          (materialOf(tester).shape as StadiumBorder).side.color,
          SureColors(tokens).hairline,
        );
        final label = tester.widget<Text>(find.text('USD'));
        expect(label.style?.color, tokens.textSecondary);
        expect(label.style?.fontWeight, FontWeight.w500);
      },
    );
  }

  testWidgets('tapping reports the next selected value', (tester) async {
    bool? next;
    await pump(
      tester,
      SureChip(label: 'USD', selected: false, onSelected: (v) => next = v),
    );
    await tester.tap(find.byType(SureChip));
    expect(next, isTrue);

    await pump(
      tester,
      SureChip(label: 'USD', selected: true, onSelected: (v) => next = v),
    );
    await tester.tap(find.byType(SureChip));
    expect(next, isFalse);
  });

  testWidgets('exposes button + selected semantics', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      SureChip(label: 'USD', selected: true, onSelected: (_) {}),
    );
    final node = tester.getSemantics(find.byType(SureChip));
    expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(node.hasFlag(SemanticsFlag.isSelected), isTrue);
    handle.dispose();
  });

  testWidgets('a chip without onSelected is non-interactive', (tester) async {
    await pump(tester, const SureChip(label: 'USD'));
    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
  });

  testWidgets('enabled: false is non-interactive and dimmed', (tester) async {
    var taps = 0;
    await pump(
      tester,
      SureChip(label: 'USD', enabled: false, onSelected: (_) => taps++),
    );
    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.5);
    await tester.tap(find.byType(SureChip));
    expect(taps, 0);
  });

  testWidgets('a dropdown chip ends with a chevron', (tester) async {
    await pump(tester, SureChip(label: 'Category', dropdown: true, onSelected: (_) {}));
    expect(
      tester.widget<SureIcon>(find.byType(SureIcon)).name,
      SureIcons.chevronDown,
    );
  });

  testWidgets('the margin around the pill is tappable too', (tester) async {
    var taps = 0;
    await pump(tester, SureChip(label: 'USD', onSelected: (_) => taps++));
    final rect = tester.getRect(find.byType(SureChip));
    // 2 px inside the top edge: outside the 32 px pill, inside the 44 px hit area.
    await tester.tapAt(Offset(rect.center.dx, rect.top + 2));
    expect(taps, 1);
  });

  testWidgets('selecting plays the selection haptic', (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add(call.arguments as String);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await pump(tester, SureChip(label: 'USD', onSelected: (_) {}));
    await tester.tap(find.byType(SureChip));
    expect(calls, ['HapticFeedbackType.selectionClick']);
  });

  testWidgets('a long label ellipsizes at 320 px without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(
      tester,
      SureChip(label: 'A very long category name ' * 4, dropdown: true, onSelected: (_) {}),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(SureChip)).width, lessThanOrEqualTo(320));
  });

  testWidgets('meets the minimum tap-target height', (tester) async {
    await pump(tester, const SureChip(label: 'USD'));
    expect(
        tester.getSize(find.byType(SureChip)).height, greaterThanOrEqualTo(44));
  });
}
