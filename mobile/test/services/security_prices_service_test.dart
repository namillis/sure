import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/services/security_prices_service.dart';

void main() {
  group('SecurityPricesService.createPrice', () {
    Future<Map<String, dynamic>> post(MockClient client) =>
        SecurityPricesService(client: client).createPrice(
          accessToken: 'token',
          securityId: 'sec_1',
          price: '12.5',
          date: '2026-11-10',
          currency: 'USD',
        );

    test('posts security_id and one price row, parses the result', () async {
      final result = await post(MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/security_prices');
        expect(request.headers['Authorization'], 'Bearer token');
        expect(request.headers['Content-Type'], startsWith('application/json'));
        expect(jsonDecode(request.body), {
          'security_id': 'sec_1',
          'prices': [
            {'date': '2026-11-10', 'price': '12.5', 'currency': 'USD'},
          ],
        });
        return http.Response(
          '{"security_id":"sec_1","currency":"USD","created":1,"updated":0,'
          '"start_date":"2026-11-10","end_date":"2026-11-10"}',
          201,
        );
      }));

      expect(result['success'], true);
      expect(result['result']['created'], 1);
      expect(result['result']['currency'], 'USD');
    });

    test('reports the self-hosted-only refusal with its code', () async {
      final result = await post(MockClient((_) async => http.Response(
            '{"error":"self_hosted_only","message":"Security prices are shared '
            'across families, so importing them is only available on '
            'self-hosted instances"}',
            403,
          )));

      expect(result['success'], false);
      expect(result['code'], SecurityPricesService.selfHostedOnly);
      expect(result['error'], contains('self-hosted'));
    });

    test('joins per-row validation messages', () async {
      final result = await post(MockClient((_) async => http.Response(
            '{"error":"validation_failed","message":"Prices were not imported",'
            '"errors":[{"index":0,"message":"currency must be EUR, the '
            'currency of your trades in this security"}]}',
            422,
          )));

      expect(result['success'], false);
      expect(result['code'], 'validation_failed');
      expect(
        result['error'],
        'Prices were not imported: currency must be EUR, the currency of '
        'your trades in this security',
      );
    });

    test('returns the not-found code for an unpriceable security', () async {
      final result = await post(MockClient((_) async => http.Response(
            '{"error":"record_not_found","message":"The requested resource '
            'was not found"}',
            404,
          )));

      expect(result['code'], SecurityPricesService.notFound);
      expect(result['error'], 'The requested resource was not found');
    });

    test('maps 401 to unauthorized', () async {
      final result =
          await post(MockClient((_) async => http.Response('{}', 401)));
      expect(result, {'success': false, 'error': 'unauthorized'});
    });

    test('falls back on a non-JSON error body and a network failure', () async {
      final html = await post(
          MockClient((_) async => http.Response('<html>oops</html>', 500)));
      expect(html['error'], 'Failed to save the price');
      expect(html['code'], isNull);

      final thrown = await post(
          MockClient((_) async => throw http.ClientException('offline')));
      expect(thrown['success'], false);
      expect(thrown['error'], 'Unable to save the price.');
    });
  });
}
