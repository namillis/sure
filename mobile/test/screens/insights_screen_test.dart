import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/screens/insights_screen.dart';
import 'package:sure_mobile/services/insights_service.dart';
import 'package:sure_mobile/theme/sure_colors.dart';
import 'package:sure_mobile/widgets/ds/ds.dart';

import '../support/l10n_harness.dart';

Map<String, dynamic> insight(String id, String title,
        {String priority = 'medium'}) =>
    {
      'id': id,
      'type': 'spending_spike',
      'title': title,
      'body': 'Body of $title',
      'priority': priority,
      'status': 'active',
      'generated_at': '2026-11-09T08:00:00Z',
    };

String index(List<Map<String, dynamic>> items) =>
    jsonEncode({'insights': items});

void main() {
  Future<void> pump(WidgetTester tester, MockClient client,
      {Future<void> Function()? onUnauthorized}) async {
    await pumpLocalized(
      tester,
      InsightsScreen(
        service: InsightsService(client: client),
        accessTokenLoader: () async => 'token',
        onUnauthorized: onUnauthorized ?? () async {},
      ),
    );
  }

  testWidgets('lists every insight with its body', (tester) async {
    await pump(
      tester,
      MockClient((_) async => http.Response(
          index([
            insight('i1', 'Dining is up', priority: 'high'),
            insight('i2', 'Rent posted'),
            insight('i3', 'Third'),
            insight('i4', 'Fourth'),
          ]),
          200)),
    );

    expect(find.text('Dining is up'), findsOneWidget);
    expect(find.text('Body of Dining is up'), findsOneWidget);
    expect(find.textContaining('High priority'), findsOneWidget);
    expect(find.text('Fourth'), findsOneWidget);
    expect(find.text('Dismiss'), findsNWidgets(4));
  });

  testWidgets('panels tint the icon by priority and show a short date',
      (tester) async {
    await pump(
      tester,
      MockClient((_) async => http.Response(
          index([
            insight('i1', 'High one', priority: 'high'),
            insight('i2', 'Low one', priority: 'low'),
          ]),
          200)),
    );

    final palette = SureColors.of(tester.element(find.text('High one'))).palette;
    Color fill(String id) => ((tester
            .widget<Container>(find.byKey(ValueKey('insightIcon-$id')))
            .decoration!) as BoxDecoration)
        .color!;
    expect(fill('i1'), palette.warning.withValues(alpha: 0.15));
    expect(fill('i2'), palette.surfaceInset);

    final day = SureDates.short(
        DateTime.parse('2026-11-09T08:00:00Z').toLocal(),
        locale: 'en');
    expect(find.text('High priority · $day'), findsOneWidget);
    expect(find.text(day), findsOneWidget);
    expect(find.byType(SurePanel), findsNWidgets(2));
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('opened from Home, the back link says Home', (tester) async {
    await pumpLocalized(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => InsightsScreen(
              service: InsightsService(
                  client:
                      MockClient((_) async => http.Response(index([]), 200))),
              accessTokenLoader: () async => 'token',
              onUnauthorized: () async {},
            ),
          )),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SureBackButton, 'Home'), findsOneWidget);
  });

  testWidgets('dismiss removes at once and stays gone on success',
      (tester) async {
    final ack = Completer<http.Response>();
    final patched = <String>[];
    await pump(
      tester,
      MockClient((request) async {
        if (request.method == 'PATCH') {
          patched.add(request.url.path);
          return ack.future;
        }
        return http.Response(
            index([insight('i1', 'First'), insight('i2', 'Second')]), 200);
      }),
    );

    await tester.tap(find.text('Dismiss').first);
    await tester.pump();
    expect(find.text('First'), findsNothing, reason: 'optimistic removal');
    expect(patched, ['/api/v1/insights/i1/acknowledge']);

    ack.complete(http.Response('', 204));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('a failed dismiss puts the insight back in place',
      (tester) async {
    await pump(
      tester,
      MockClient((request) async {
        if (request.method == 'PATCH') return http.Response('{}', 500);
        return http.Response(
            index([
              insight('i1', 'First'),
              insight('i2', 'Second'),
              insight('i3', 'Third'),
            ]),
            200);
      }),
    );

    await tester.tap(find.text('Dismiss').at(1));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't dismiss the insight"), findsOneWidget);
    final second = tester.getTopLeft(find.text('Second')).dy;
    expect(tester.getTopLeft(find.text('First')).dy, lessThan(second));
    expect(tester.getTopLeft(find.text('Third')).dy, greaterThan(second));
  });

  testWidgets('swiping dismisses', (tester) async {
    final patched = <String>[];
    await pump(
      tester,
      MockClient((request) async {
        if (request.method == 'PATCH') {
          patched.add(request.url.path);
          return http.Response('', 204);
        }
        return http.Response(index([insight('i1', 'First')]), 200);
      }),
    );

    await tester.drag(find.text('First'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(patched, ['/api/v1/insights/i1/acknowledge']);
    expect(find.text('No insights right now'), findsOneWidget);
  });

  for (final status in [403, 404]) {
    testWidgets('$status explains that insights are off', (tester) async {
      await pump(
        tester,
        MockClient((_) async => http.Response(
            '{"error":"feature_disabled","message":"Preview features are not enabled for this user"}',
            status)),
      );
      expect(find.text("Insights aren't turned on"), findsOneWidget);
      expect(find.text('Try Again'), findsNothing);
    });
  }

  testWidgets('empty state', (tester) async {
    await pump(tester, MockClient((_) async => http.Response(index([]), 200)));
    expect(find.text('No insights right now'), findsOneWidget);
  });

  testWidgets('error state', (tester) async {
    await pump(tester, MockClient((_) async => http.Response('{}', 500)));
    expect(find.text("Couldn't load insights."), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
  });

  testWidgets('401 signs out', (tester) async {
    var signedOut = false;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: InsightsScreen(
        service: InsightsService(
            client: MockClient((_) async => http.Response('{}', 401))),
        accessTokenLoader: () async => 'token',
        onUnauthorized: () async => signedOut = true,
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(signedOut, true);
  });
}
