import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/theme/sure_colors.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/theme/sure_tokens.dart';
import 'package:sure_mobile/widgets/ds/sure_large_title.dart';
import 'package:sure_mobile/widgets/ds/sure_sheet.dart';
import 'package:sure_mobile/widgets/ds/sure_tab_bar.dart';
import 'package:sure_mobile/widgets/sure_icon.dart';

import '../../support/ds_harness.dart';

void main() {
  group('sheet', () {
    Future<void> openSheet(
      WidgetTester tester, {
      Brightness brightness = Brightness.light,
      VoidCallback? onAction,
      bool busy = false,
      double width = 390,
    }) async {
      await pumpDs(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showSureSheet<void>(
              context: context,
              builder: (_) => SureSheet(
                title: 'A sheet title long enough to ellipsize ' * 3,
                onAction: onAction,
                busy: busy,
                child: const SizedBox(height: 200, child: Text('Body')),
              ),
            ),
            child: const Text('open'),
          ),
        ),
        brightness: brightness,
        width: width,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    for (final brightness in brightnesses) {
      testWidgets(
          'grabber, Cancel and Save, rounded top (${brightness.name}, '
          '320 px)', (tester) async {
        var saves = 0;
        await openSheet(tester,
            brightness: brightness, onAction: () => saves++, width: 320);
        expect(tester.takeException(), isNull);
        final tokens =
            brightness == Brightness.dark ? SureTokens.dark : SureTokens.light;

        expect(find.byType(SureSheetGrabber), findsOneWidget);
        expect(
            tester.getSize(find.descendant(
                of: find.byType(SureSheetGrabber),
                matching: find.byType(Container))),
            const Size(36, 5));
        final cancel = tester.widget<Text>(find.text('Cancel'));
        expect(cancel.style?.fontSize, 16);
        final save = tester.widget<Text>(find.text('Save'));
        expect(save.style?.fontWeight, FontWeight.w600);

        final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
        expect(sheet.backgroundColor, tokens.surface);
        expect(
          (sheet.shape as RoundedRectangleBorder).borderRadius,
          const BorderRadius.vertical(
              top: Radius.circular(SureTheme.sheetRadius)),
        );

        await tester.tap(find.text('Save'));
        expect(saves, 1);
      });
    }

    testWidgets('Cancel closes the sheet', (tester) async {
      await openSheet(tester, onAction: () {});
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Body'), findsNothing);
    });

    testWidgets('busy shows a spinner instead of Save', (tester) async {
      await pumpDs(
        tester,
        SureSheet(
          title: 'T',
          onAction: () {},
          busy: true,
          child: const SizedBox(height: 10),
        ),
      );
      expect(find.text('Save'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('no toolbar when there is no title or action', (tester) async {
      await pumpDs(tester, const SureSheet(child: Text('Only body')));
      expect(find.text('Cancel'), findsNothing);
      expect(find.byType(SureSheetGrabber), findsOneWidget);
    });
  });

  group('tab bar', () {
    const items = [
      SureTabItem(icon: SureIcons.house, label: 'Home'),
      SureTabItem(icon: SureIcons.receipt, label: 'Activity'),
      SureTabItem(icon: SureIcons.chartPie, label: 'Plan'),
      SureTabItem(icon: SureIcons.trendingUp, label: 'Invest'),
      SureTabItem(icon: SureIcons.messageCircle, label: 'Assistant'),
    ];

    for (final brightness in brightnesses) {
      testWidgets(
          'selected primary 600, others subdued, top hairline '
          '(${brightness.name}, 320 px)', (tester) async {
        int? tapped;
        await pumpDs(
          tester,
          Align(
            alignment: Alignment.bottomCenter,
            child: SureTabBar(
                items: items, currentIndex: 1, onSelected: (i) => tapped = i),
          ),
          brightness: brightness,
          width: 320,
        );
        expect(tester.takeException(), isNull);
        final tokens =
            brightness == Brightness.dark ? SureTokens.dark : SureTokens.light;
        final selected = tester.widget<Text>(find.text('Activity'));
        expect(selected.style?.color, tokens.textPrimary);
        expect(selected.style?.fontWeight, FontWeight.w600);
        final other = tester.widget<Text>(find.text('Home'));
        expect(other.style?.color, tokens.textSubdued);
        expect(find.byType(BackdropFilter), findsOneWidget);
        final deco = tester
            .widget<DecoratedBox>(find
                .descendant(
                    of: find.byType(SureTabBar),
                    matching: find.byType(DecoratedBox))
                .first)
            .decoration as BoxDecoration;
        expect((deco.border as Border).top.color, SureColors(tokens).hairline);
        expect(find.byType(NavigationBar), findsNothing);

        await tester.tap(find.text('Invest'));
        expect(tapped, 3);
      });
    }
  });

  group('large title', () {
    Widget page({Brightness brightness = Brightness.light}) =>
        SureLargeTitleScaffold(
          title: 'Activity',
          subtitle: 'Brokerage · synced 9h ago',
          actions: [
            SureNavIconButton(
                icon: SureIcons.plus, semanticLabel: 'New', onPressed: () {}),
          ],
          slivers: [
            SliverList.list(children: [
              for (var i = 0; i < 40; i++)
                SizedBox(height: 44, child: Text('Row $i')),
            ]),
          ],
        );

    Finder title() => find.text('Activity');

    double opacityOf(WidgetTester tester, Finder text) => tester
        .widget<Opacity>(
            find.ancestor(of: text, matching: find.byType(Opacity)).first)
        .opacity;

    for (final brightness in brightnesses) {
      testWidgets(
          'large title collapses to a small centered title '
          '(${brightness.name})', (tester) async {
        await tester.pumpWidget(MaterialApp(
          theme:
              brightness == Brightness.dark ? SureTheme.dark : SureTheme.light,
          home: page(brightness: brightness),
        ));
        // Two copies: the small bar title (hidden) and the large one.
        expect(title(), findsNWidgets(2));
        final small = title().first;
        final large = title().last;
        expect(tester.widget<Text>(large).style?.fontSize, 32);
        expect(tester.widget<Text>(large).style?.fontWeight, FontWeight.w600);
        expect(tester.widget<Text>(small).style?.fontSize, 17);
        expect(opacityOf(tester, small), 0);
        expect(opacityOf(tester, large), 1);
        final smallX = tester.getCenter(small).dx;
        expect(smallX, closeTo(400, 1)); // centered in the 800 px test view

        await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(opacityOf(tester, title().first), 1);
        expect(
            find.text('Brokerage · synced 9h ago').hitTestable(), findsNothing);
        expect(find.bySemanticsLabel('New'), findsOneWidget);
      });
    }

    testWidgets('a pushed page gets a back button that pops', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: SureTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => page())),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byType(SureBackButton), findsOneWidget);
      await tester.tap(find.byType(SureBackButton));
      await tester.pumpAndSettle();
      expect(find.text('go'), findsOneWidget);
    });

    testWidgets('a long title ellipsizes at 320 px', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: SureTheme.light,
        home: SureLargeTitleScaffold(
          title: 'Chase Sapphire Preferred Visa Signature Card',
          leading: const SureBackButton(label: 'Home'),
          actions: [
            SureNavIconButton(
                icon: SureIcons.ellipsis,
                semanticLabel: 'More',
                onPressed: () {}),
          ],
          slivers: const [SliverToBoxAdapter(child: SizedBox(height: 2000))],
        ),
      ));
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
