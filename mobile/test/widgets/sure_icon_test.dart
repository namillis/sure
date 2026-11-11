import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/widgets/sure_icon.dart';

void main() {
  SvgPicture svg(WidgetTester tester) =>
      tester.widget<SvgPicture>(find.byType(SvgPicture));

  testWidgets('renders the named Lucide asset at the requested size',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SureIcon(SureIcons.wallet, size: SureIconSize.lg),
      ),
    );
    expect(svg(tester).width, SureIconSize.lg);
    expect(svg(tester).height, SureIconSize.lg);
  });

  testWidgets('paints at its size inside a larger tight-constrained parent',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: SureIcon(SureIcons.landmark, size: SureIconSize.lg),
          ),
        ),
      ),
    );
    // The glyph must stay 24 (not stretch to the 48 container) — regression for
    // the account-card icon rendering at 2x.
    expect(tester.getSize(find.byType(SvgPicture)), const Size(24, 24));
  });

  testWidgets('falls back to the ambient IconTheme size when size is null',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: IconTheme(
          data: IconThemeData(size: 30),
          child: SureIcon(SureIcons.refresh),
        ),
      ),
    );
    expect(svg(tester).width, 30);
    expect(svg(tester).height, 30);
  });

  testWidgets('a meaningful icon exposes its label; a decorative one does not',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SureIcon(SureIcons.refresh, semanticLabel: 'Refresh'),
      ),
    );
    expect(find.bySemanticsLabel('Refresh'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(home: SureIcon(SureIcons.wallet)),
    );
    expect(find.bySemanticsLabel('wallet'), findsNothing);
  });

  test('every SureIcons name used by the app ships as an SVG', () {
    const names = [
      SureIcons.landmark,
      SureIcons.creditCard,
      SureIcons.trendingUp,
      SureIcons.trendingDown,
      SureIcons.receipt,
      SureIcons.house,
      SureIcons.car,
      SureIcons.bitcoin,
      SureIcons.shapes,
      SureIcons.handCoins,
      SureIcons.wallet,
      SureIcons.circleAlert,
      SureIcons.circleCheck,
      SureIcons.cloudCheck,
      SureIcons.refresh,
      SureIcons.chevronUp,
      SureIcons.chevronDown,
      SureIcons.chevronRight,
      SureIcons.chevronLeft,
      SureIcons.arrowDown,
      SureIcons.arrowUp,
      SureIcons.arrowUpRight,
      SureIcons.arrowLeftRight,
      SureIcons.calendar,
      SureIcons.chartLine,
      SureIcons.chartPie,
      SureIcons.check,
      SureIcons.circleDashed,
      SureIcons.circlePlus,
      SureIcons.circleQuestionMark,
      SureIcons.circleX,
      SureIcons.clock,
      SureIcons.cloudOff,
      SureIcons.cloudUpload,
      SureIcons.coins,
      SureIcons.ellipsis,
      SureIcons.externalLink,
      SureIcons.eye,
      SureIcons.eyeOff,
      SureIcons.inbox,
      SureIcons.info,
      SureIcons.lightbulb,
      SureIcons.listChecks,
      SureIcons.messageCircle,
      SureIcons.minus,
      SureIcons.pencil,
      SureIcons.piggyBank,
      SureIcons.plus,
      SureIcons.repeat,
      SureIcons.search,
      SureIcons.settings,
      SureIcons.sparkles,
      SureIcons.split,
      SureIcons.squareCheck,
      SureIcons.store,
      SureIcons.stickyNote,
      SureIcons.tag,
      SureIcons.trash,
      SureIcons.triangleAlert,
      SureIcons.x,
    ];
    for (final name in names) {
      expect(File('assets/icons/lucide/$name.svg').existsSync(), isTrue,
          reason: name);
    }
    expect(File('assets/icons/lucide/LICENSE').readAsStringSync(),
        contains('ISC License'));
  });
}
