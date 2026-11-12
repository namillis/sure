import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/screens/web_view_screen.dart';
import 'package:sure_mobile/theme/sure_colors.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';

import '../support/l10n_harness.dart';

void main() {
  Future<void> pushBar(WidgetTester tester, WebViewTitleBar bar) async {
    await pumpLocalized(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => Scaffold(body: Column(children: [bar])),
          )),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('labeled back link, title and a link-colored progress bar',
      (tester) async {
    var opened = 0;
    await pushBar(
      tester,
      WebViewTitleBar(
        title: 'Goals',
        backLabel: 'Settings',
        progress: 0.4,
        onOpenExternally: () => opened++,
      ),
    );

    expect(find.widgetWithText(SureBackButton, 'Settings'), findsOneWidget);
    expect(find.text('Goals'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('webViewProgress')));
    final palette = SureColors.of(tester.element(find.text('Goals'))).palette;
    expect(bar.color, palette.link);
    expect(bar.value, 0.4);
    expect(bar.minHeight, 2);

    // No page history: no in-page back/forward.
    expect(find.bySemanticsLabel('Back'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('webViewOpenExternally')));
    expect(opened, 1);
  });

  testWidgets('no progress bar once loaded; history shows back/forward',
      (tester) async {
    await pushBar(
      tester,
      WebViewTitleBar(
        title: 'Goals',
        onOpenExternally: () {},
        onWebBack: () {},
        onWebForward: () {},
      ),
    );
    expect(find.byKey(const ValueKey('webViewProgress')), findsNothing);
    expect(find.byType(SureNavIconButton), findsNWidgets(3));
  });
}
