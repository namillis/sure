import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/screens/insights_screen.dart';
import 'package:sure_mobile/services/insights_service.dart';
import 'package:sure_mobile/widgets/ds/sure_panel.dart';
import 'package:sure_mobile/widgets/insights_card.dart';
import 'package:sure_mobile/widgets/sure_list_group.dart';

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

  testWidgets('one row with the top insight; tapping opens the list',
      (tester) async {
    var gets = 0;
    await pump(
      tester,
      MockClient((request) async {
        gets++;
        return http.Response(
          jsonEncode({
            'insights': [
              insight('i1', 'Dining is up', priority: 'high'),
              insight('i2', 'Rent posted'),
            ],
          }),
          200,
        );
      }),
    );

    expect(find.byType(SurePanel), findsOneWidget);
    expect(find.byType(SureListRow), findsOneWidget);
    expect(find.text('Dining is up'), findsOneWidget);
    expect(find.text('Rent posted'), findsNothing);

    await tester.tap(find.text('Dining is up'));
    await tester.pumpAndSettle();
    expect(find.byType(InsightsScreen), findsOneWidget);
    expect(find.text('Rent posted'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(gets, 3, reason: 'row, screen, and row reload on return');
  });

  for (final status in [403, 404, 500, 401]) {
    testWidgets('renders nothing on $status', (tester) async {
      await pump(
        tester,
        MockClient((_) async => http.Response(
            '{"error":"feature_disabled"}', status)),
      );
      expect(find.byType(SurePanel), findsNothing);
    });
  }

  testWidgets('renders nothing with no insights', (tester) async {
    await pump(tester,
        MockClient((_) async => http.Response('{"insights":[]}', 200)));
    expect(find.byType(SurePanel), findsNothing);
  });

  testWidgets('the row is at least 44pt tall', (tester) async {
    await pump(
      tester,
      MockClient((_) async => http.Response(
          jsonEncode({'insights': [insight('i1', 'Only one')]}), 200)),
    );
    expect(tester.getSize(find.byType(SureListRow)).height,
        greaterThanOrEqualTo(44));
  });
}
