import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/screens/log_viewer_screen.dart';
import 'package:sure_mobile/services/log_service.dart';
import 'package:sure_mobile/theme/sure_colors.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';

import '../support/l10n_harness.dart';

void main() {
  final shared = <String>[];

  setUp(() {
    shared.clear();
    LogService.instance.clear();
    LogService.instance.error('Sync', 'boom happened');
    LogService.instance.info('Sync', 'all fine');
  });

  tearDown(LogService.instance.clear);

  Future<void> pump(WidgetTester tester) => pumpLocalized(
        tester,
        ChangeNotifierProvider<LogService>.value(
          value: LogService.instance,
          child: LogViewerScreen(
            sharer: (text, _) async => shared.add(text),
          ),
        ),
      );

  testWidgets('rows are mono text with a level dot in one panel',
      (tester) async {
    await pump(tester);
    expect(find.text('[Sync] boom happened'), findsOneWidget);
    expect(find.text('[Sync] all fine'), findsOneWidget);

    final palette =
        SureColors.of(tester.element(find.text('[Sync] all fine'))).palette;
    final dots = tester
        .widgetList<Container>(find.byKey(const ValueKey('logLevelDot')))
        .map((c) => (c.decoration! as BoxDecoration).color)
        .toList();
    expect(dots, contains(palette.destructive));
    expect(dots, contains(palette.link));
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('level chips filter the list', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('logLevel-ERROR')));
    await tester.pumpAndSettle();
    expect(find.text('[Sync] boom happened'), findsOneWidget);
    expect(find.text('[Sync] all fine'), findsNothing);
    expect(
        tester
            .widget<SureChip>(find.byKey(const ValueKey('logLevel-ERROR')))
            .selected,
        isTrue);
  });

  testWidgets('share hands the exported logs to the sharer', (tester) async {
    await pump(tester);
    await tester.tap(find.bySemanticsLabel('Share logs'));
    await tester.pumpAndSettle();
    expect(shared.single, contains('boom happened'));
  });

  testWidgets('clear asks first, then shows the empty state', (tester) async {
    await pump(tester);
    await tester.tap(find.bySemanticsLabel('Clear logs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('No logs yet'), findsOneWidget);
    expect(find.byType(SureEmptyState), findsOneWidget);
  });
}
