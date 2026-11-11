import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/services/connectivity_service.dart';
import 'package:sure_mobile/theme/sure_tokens.dart';
import 'package:sure_mobile/widgets/connectivity_banner.dart';
import 'package:sure_mobile/widgets/ds/sure_banner.dart';

import '../support/ds_harness.dart';
import '../support/home_fixtures.dart';

void main() {
  final now = DateTime(2026, 11, 11, 12);

  Future<void> pump(
    WidgetTester tester, {
    required bool offline,
    DateTime? updatedAt,
    Brightness brightness = Brightness.light,
  }) =>
      pumpDs(
        tester,
        ChangeNotifierProvider<ConnectivityService>(
          create: (_) => FakeConnectivity(offline: offline),
          child: ConnectivityBanner(updatedAt: updatedAt, clock: () => now),
        ),
        brightness: brightness,
      );

  for (final brightness in brightnesses) {
    testWidgets('offline with saved data says how old it is '
        '(${brightness.name})', (tester) async {
      await pump(
        tester,
        offline: true,
        updatedAt: now.subtract(const Duration(hours: 2, minutes: 10)),
        brightness: brightness,
      );
      expect(find.byType(SureBanner), findsOneWidget);
      expect(find.text('Offline · showing data from 2h ago'), findsOneWidget);
      final fill = tester
          .widget<Container>(find.descendant(
              of: find.byType(SureBanner), matching: find.byType(Container)))
          .decoration as BoxDecoration;
      final warning = brightness == Brightness.dark
          ? SureTokens.dark.warning
          : SureTokens.light.warning;
      expect(fill.color, warning.withValues(alpha: 0.15));
    });
  }

  testWidgets('offline with fresh or unknown data', (tester) async {
    await pump(tester,
        offline: true, updatedAt: now.subtract(const Duration(seconds: 20)));
    expect(find.text('Offline · showing data from just now'), findsOneWidget);

    await pump(tester, offline: true);
    expect(find.text("You're offline. Data shown may be out of date."),
        findsOneWidget);
  });

  testWidgets('online with nothing pending renders nothing', (tester) async {
    await pump(tester, offline: false, updatedAt: now);
    expect(find.byType(SureBanner), findsNothing);
  });
}
