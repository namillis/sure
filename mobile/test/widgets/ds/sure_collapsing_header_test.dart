import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';

import '../../support/ds_harness.dart';

void main() {
  Widget page({String? subtitle, Widget? pinned}) => SureCollapsingHeader(
        navBarKey: const ValueKey('bar'),
        title: 'Invest',
        subtitle: subtitle,
        subtitleKey: const ValueKey('sub'),
        leading: const SureBackButton(label: 'Home'),
        actions: [
          SureNavTextButton(label: 'Edit', onPressed: () {}),
        ],
        headerSlivers: const [
          SliverToBoxAdapter(child: SizedBox(height: 300, child: Text('hero'))),
        ],
        pinned: pinned,
        pinnedKey: const ValueKey('pinned'),
        body: ListView.builder(
          itemCount: 60,
          itemBuilder: (context, i) =>
              SizedBox(height: 44, child: Text('row $i')),
        ),
      );

  double smallTitleOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(find.descendant(
          of: find.byKey(const ValueKey('bar')),
          matching: find.byType(AnimatedOpacity)))
      .opacity;

  testWidgets('small title fades in once the large title scrolls away',
      (tester) async {
    await pumpDs(tester, page(subtitle: '3 accounts'));
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.byKey(const ValueKey('sub')), findsOneWidget);
    expect(smallTitleOpacity(tester), 0);

    await tester.drag(find.text('hero'), const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(smallTitleOpacity(tester), 1);
  });

  testWidgets('pinned control stays under the bar while the body scrolls',
      (tester) async {
    await pumpDs(
      tester,
      page(pinned: const SizedBox(height: 32, child: Text('switcher'))),
    );
    await tester.drag(find.text('row 0'), const Offset(0, -1200));
    await tester.pumpAndSettle();
    final barBottom =
        tester.getBottomLeft(find.byKey(const ValueKey('bar'))).dy;
    expect(tester.getTopLeft(find.byKey(const ValueKey('pinned'))).dy,
        barBottom);
    expect(find.text('hero'), findsNothing);
  });

  testWidgets('no pinned control: body sits right under the header',
      (tester) async {
    await pumpDs(tester, page());
    expect(find.byKey(const ValueKey('pinned')), findsNothing);
    expect(find.byKey(const ValueKey('sub')), findsNothing);
    expect(find.text('row 0'), findsOneWidget);
  });

  testWidgets('section header with a label and an icon shows both',
      (tester) async {
    var taps = 0;
    await pumpDs(
      tester,
      SureSectionHeader(
        label: 'Categories',
        actionLabel: 'Edit on web',
        actionIcon: SureIcons.arrowUpRight,
        onAction: () => taps++,
      ),
    );
    expect(find.text('Edit on web'), findsOneWidget);
    final icon = tester.widget<SureIcon>(find.byType(SureIcon));
    expect(icon.name, SureIcons.arrowUpRight);
    await tester.tap(find.text('Edit on web'));
    expect(taps, 1);
  });

  testWidgets('disabled list row is dimmed and ignores taps', (tester) async {
    var taps = 0;
    await pumpDs(
      tester,
      SureListRow(title: 'Merchant', onTap: () => taps++, enabled: false),
    );
    await tester.tap(find.text('Merchant'));
    expect(taps, 0);
    final opacity = tester.widget<Opacity>(find.ancestor(
        of: find.text('Merchant'), matching: find.byType(Opacity)));
    expect(opacity.opacity, 0.5);
  });

  testWidgets('button panel: tap, busy and disabled', (tester) async {
    var taps = 0;
    Future<void> pump({bool busy = false, bool enabled = true}) => pumpDs(
          tester,
          SureButtonPanel(
            label: 'Delete',
            destructive: true,
            busy: busy,
            onPressed: enabled ? () => taps++ : null,
          ),
        );

    await pump();
    await tester.tap(find.text('Delete'));
    expect(taps, 1);

    await pump(busy: true);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(SureButtonPanel));
    expect(taps, 1);

    await pump(enabled: false);
    await tester.tap(find.text('Delete'));
    expect(taps, 1);
    expect(
      tester
          .widget<Opacity>(find.ancestor(
              of: find.text('Delete'), matching: find.byType(Opacity)))
          .opacity,
      0.5,
    );
  });

  testWidgets('sheet action key finds the action button', (tester) async {
    var saved = false;
    await pumpDs(
      tester,
      SureSheet(
        title: 'Category',
        actionKey: const ValueKey('save'),
        onAction: () => saved = true,
        child: const Text('body'),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('save')));
    expect(saved, isTrue);
  });
}
