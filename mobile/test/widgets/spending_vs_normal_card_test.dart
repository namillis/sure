import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/services/spending_vs_normal_service.dart';
import 'package:sure_mobile/widgets/ds/sure_panel.dart';
import 'package:sure_mobile/widgets/spending_vs_normal_card.dart';

import '../support/l10n_harness.dart';
import '../support/recurring_fixtures.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    MockClient client, {
    void Function()? onOpen,
  }) =>
      pumpLocalized(
        tester,
        SpendingVsNormalCard(
          service: SpendingVsNormalService(client: client),
          accessTokenLoader: () async => 'token',
          onOpen: onOpen,
        ),
      );

  MockClient respond(Map<String, dynamic> json) =>
      MockClient((_) async => http.Response(jsonEncode(json), 200));

  testWidgets('one row: spending above normal, tap opens the detail',
      (tester) async {
    var opened = 0;
    await pump(tester, respond(spendingJson()), onOpen: () => opened++);

    expect(find.byType(SurePanel), findsOneWidget);
    expect(find.text('Spending 20% above normal'), findsOneWidget);
    await tester.tap(find.text('Spending 20% above normal'));
    expect(opened, 1);
  });

  testWidgets('below normal', (tester) async {
    await pump(
        tester, respond({...spendingJson(), 'total': '800.0'}));
    expect(find.text('Spending 20% below normal'), findsOneWidget);
  });

  testWidgets('about normal', (tester) async {
    await pump(
        tester, respond({...spendingJson(), 'total': '1001.0'}));
    expect(find.text('Spending about normal'), findsOneWidget);
  });

  testWidgets('renders nothing without history to compare', (tester) async {
    await pump(tester, respond(spendingJson(comparable: false)));
    expect(find.byType(SurePanel), findsNothing);
  });

  testWidgets('renders nothing with no categories', (tester) async {
    await pump(tester, respond(spendingJson(categories: [])));
    expect(find.byType(SurePanel), findsNothing);
  });

  for (final status in [403, 404, 500]) {
    testWidgets('renders nothing on $status', (tester) async {
      await pump(tester, MockClient((_) async => http.Response('{}', status)));
      expect(find.byType(SurePanel), findsNothing);
    });
  }
}
