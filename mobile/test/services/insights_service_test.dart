import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/insight.dart';
import 'package:sure_mobile/services/insights_service.dart';

void main() {
  group('InsightsService', () {
    test('getInsights parses the index', () async {
      final service = InsightsService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/insights');
          expect(request.headers['Authorization'], 'Bearer token');
          return http.Response(
            '{"insights":[{"id":"i1","type":"spending_spike",'
            '"title":"Dining is up","body":"You spent 32% more.",'
            '"priority":"high","status":"active",'
            '"generated_at":"2026-11-09T08:00:00Z"}]}',
            200,
          );
        }),
      );

      final result = await service.getInsights(accessToken: 'token');

      expect(result['success'], true);
      final insights = (result['insights'] as List).cast<Insight>();
      expect(insights.single.title, 'Dining is up');
      expect(insights.single.priority, 'high');
      expect(insights.single.generatedAt, DateTime.utc(2026, 11, 9, 8));
    });

    test('getInsights returns unauthorized on 401', () async {
      final service = InsightsService(
          client: MockClient((_) async => http.Response('{}', 401)));
      expect((await service.getInsights(accessToken: 't'))['error'],
          'unauthorized');
    });

    test('feature disabled (403) and missing endpoint (404) are unavailable',
        () async {
      for (final status in [403, 404]) {
        final service = InsightsService(
          client: MockClient((_) async => http.Response(
              '{"error":"feature_disabled","message":"Preview features are not enabled for this user"}',
              status)),
        );
        expect(await service.getInsights(accessToken: 't'),
            {'success': false, 'error': 'unavailable'});
      }
    });

    test('acknowledge patches the member acknowledge path', () async {
      final service = InsightsService(
        client: MockClient((request) async {
          expect(request.method, 'PATCH');
          expect(request.url.path, '/api/v1/insights/i1/acknowledge');
          return http.Response('', 204);
        }),
      );
      expect(await service.acknowledge(accessToken: 't', id: 'i1'),
          {'success': true});
    });

    test('acknowledge returns unauthorized on 401', () async {
      final service = InsightsService(
          client: MockClient((_) async => http.Response('{}', 401)));
      expect((await service.acknowledge(accessToken: 't', id: 'i1'))['error'],
          'unauthorized');
    });
  });
}
