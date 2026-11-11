import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/screens/debug/ds_gallery_screen.dart';
import 'package:sure_mobile/widgets/ds/sure_large_title.dart';

import '../support/ds_harness.dart';

void main() {
  for (final brightness in brightnesses) {
    testWidgets('gallery builds and scrolls to the end (${brightness.name})',
        (tester) async {
      await pumpDs(tester, const DsGalleryScreen(), brightness: brightness);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Design gallery'), findsWidgets);
      expect(find.byType(SureLargeTitleHeader), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Tab bar'),
        600,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the gallery can flip its own brightness', (tester) async {
    await pumpDs(tester, const DsGalleryScreen());
    await tester.tap(find.byTooltip('Toggle light/dark'));
    await tester.pumpAndSettle();
    expect(find.textContaining('· dark'), findsOneWidget);
  });
}
