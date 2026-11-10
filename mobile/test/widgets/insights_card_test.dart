import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/services/insights_service.dart';
import 'package:sure_mobile/widgets/insights_card.dart';
import 'package:sure_mobile/widgets/sure_card.dart';

import '../support/l10n_harness.dart';

Map<String, dynamic> insight(String id, String title, {String priority = 'medium'}) => {
      'id': id,
      'type': 'spending_spike',
      'title': title,
      'body': 'Body of $title',
      'priority': priority,
      'status': 'active',
      'generated_at': '2026-11-09T08:00:00Z',
    };

void main() {
  Future<void> pump(WidgetTester tester, MockClient client) => pumpLocalized(
        tester,
        InsightsCard(
          service: InsightsService(client: client),
          accessTokenLoader: () async => 'token',
        ),
      );

  testWidgets('shows the top three, expands, and dismisses', (tester) async {
    final patched = <String>[];
    await pump(
      tester,
      MockClient((request) async {
        if (request.method == 'PATCH') {
          patched.add(request.url.path);
          return http.Response('', 204);
        }
        return http.Response(
          jsonEncode({
            'insights': [
              insight('i1', 'Dining is up', priority: 'high'),
              insight('i2', 'Rent posted'),
              insight('i3', 'Subscription renewed'),
              insight('i4', 'Fourth insight'),
            ],
          }),
          200,
        );
      }),
    );

    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Dining is up'), findsOneWidget);
    expect(find.text('High priority'), findsOneWidget);
    expect(find.text('Subscription renewed'), findsOneWidget);
    expect(find.text('Fourth insight'), findsNothing);
    expect(find.text('Body of Dining is up'), findsNothing);

    await tester.tap(find.text('Dining is up'));
    await tester.pumpAndSettle();
    expect(find.text('Body of Dining is up'), findsOneWidget);

    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(patched, ['/api/v1/insights/i1/acknowledge']);
    expect(find.text('Dining is up'), findsNothing);
    expect(find.text('Fourth insight'), findsOneWidget);
  });

  for (final status in [403, 404, 500, 401]) {
    testWidgets('renders nothing on $status', (tester) async {
      await pump(
        tester,
        MockClient((_) async => http.Response(
            '{"error":"feature_disabled"}', status)),
      );
      expect(find.byType(SureCard), findsNothing);
      expect(find.text('Insights'), findsNothing);
    });
  }

  testWidgets('renders nothing with no insights', (tester) async {
    await pump(tester,
        MockClient((_) async => http.Response('{"insights":[]}', 200)));
    expect(find.byType(SureCard), findsNothing);
  });

  testWidgets('dismiss button is at least 44pt tall', (tester) async {
    await pump(
      tester,
      MockClient((_) async => http.Response(
          jsonEncode({'insights': [insight('i1', 'Only one')]}), 200)),
    );
    await tester.tap(find.text('Only one'));
    await tester.pumpAndSettle();
    final box = tester.getSize(find.ancestor(
        of: find.text('Dismiss'), matching: find.byType(ConstrainedBox)).first);
    expect(box.height, greaterThanOrEqualTo(44));
  });
}
