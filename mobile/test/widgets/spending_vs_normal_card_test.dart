import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/services/spending_vs_normal_service.dart';
import 'package:sure_mobile/widgets/spending_vs_normal_card.dart';
import 'package:sure_mobile/widgets/sure_card.dart';

import '../support/l10n_harness.dart';
import '../support/recurring_fixtures.dart';

void main() {
  Future<void> pump(WidgetTester tester, MockClient client) => pumpLocalized(
        tester,
        SpendingVsNormalCard(
          service: SpendingVsNormalService(client: client),
          accessTokenLoader: () async => 'token',
        ),
      );

  testWidgets('shows the total against normal and top categories, expands',
      (tester) async {
    await pump(tester,
        MockClient((_) async => http.Response(jsonEncode(spendingJson()), 200)));

    expect(find.text('Spending vs normal'), findsOneWidget);
    expect(find.text(r'$1,200.00 so far'), findsOneWidget);
    expect(find.text(r'Normal $1,000.00 · 20% above normal'), findsOneWidget);
    expect(find.text('Dining +32%'), findsOneWidget);
    expect(find.text('Gifts New'), findsOneWidget);
    expect(find.text('Groceries +11%'), findsOneWidget);
    expect(find.text('Rent'), findsNothing);

    await tester.tap(find.text('Spending vs normal'));
    await tester.pumpAndSettle();
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text(r'$300.00 · normal $300.00'), findsOneWidget);
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('renders nothing without history to compare', (tester) async {
    await pump(
        tester,
        MockClient((_) async =>
            http.Response(jsonEncode(spendingJson(comparable: false)), 200)));
    expect(find.byType(SureCard), findsNothing);
  });

  testWidgets('renders nothing with no categories', (tester) async {
    await pump(
        tester,
        MockClient((_) async =>
            http.Response(jsonEncode(spendingJson(categories: [])), 200)));
    expect(find.byType(SureCard), findsNothing);
  });

  for (final status in [403, 404, 500]) {
    testWidgets('renders nothing on $status', (tester) async {
      await pump(tester, MockClient((_) async => http.Response('{}', status)));
      expect(find.byType(SureCard), findsNothing);
    });
  }
}
