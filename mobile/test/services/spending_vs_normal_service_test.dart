import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/spending_vs_normal.dart';
import 'package:sure_mobile/services/spending_vs_normal_service.dart';

import '../support/recurring_fixtures.dart';

void main() {
  group('SpendingVsNormalService', () {
    test('defaults to the current month with no query', () async {
      final service = SpendingVsNormalService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/spending_vs_normal');
          expect(request.url.queryParameters, isEmpty);
          expect(request.headers['Authorization'], 'Bearer token');
          return http.Response(jsonEncode(spendingJson()), 200);
        }),
      );

      final result = await service.getSpendingVsNormal(accessToken: 'token');

      expect(result['success'], true);
      final data = result['spending'] as SpendingVsNormal;
      expect(data.currency, 'USD');
      expect(data.comparable, true);
      expect(data.inProgress, true);
      expect(data.total, 1200);
      expect(data.normalTotal, 1000);
      expect(data.ratio, closeTo(0.2, 1e-9));
      expect(data.categories, hasLength(4));
      expect(data.categories[1].name, 'Dining');
      expect(data.categories[1].ratio, 0.32);
      expect(data.categories[3].ratio, isNull);
    });

    test('sends start_date and end_date as ISO dates', () async {
      final service = SpendingVsNormalService(
        client: MockClient((request) async {
          expect(request.url.queryParameters, {
            'start_date': '2026-10-01',
            'end_date': '2026-10-31',
          });
          return http.Response(jsonEncode(spendingJson()), 200);
        }),
      );
      final result = await service.getSpendingVsNormal(
        accessToken: 'token',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 31),
      );
      expect(result['success'], true);
    });

    test('returns unauthorized on 401 and unavailable on 403/404', () async {
      for (final entry in {401: 'unauthorized', 403: 'unavailable', 404: 'unavailable'}.entries) {
        final service = SpendingVsNormalService(
            client: MockClient((_) async => http.Response('{}', entry.key)));
        expect(
            (await service.getSpendingVsNormal(accessToken: 't'))['error'],
            entry.value);
      }
    });
  });

  test('topAboveNormal ranks by amount over normal, not ratio', () {
    final data = SpendingVsNormal.fromJson(spendingJson());
    expect(data.topAboveNormal().map((c) => c.name),
        ['Dining', 'Gifts', 'Groceries']);
    expect(data.topAboveNormal(2).map((c) => c.name), ['Dining', 'Gifts']);
  });
}
