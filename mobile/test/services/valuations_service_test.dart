import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/services/valuations_service.dart';

void main() {
  group('ValuationsService.createValuation', () {
    test('posts the valuation payload and parses the response', () async {
      final service = ValuationsService(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/valuations');
          expect(request.headers['Authorization'], 'Bearer token');
          expect(request.headers['Content-Type'], startsWith('application/json'));
          expect(jsonDecode(request.body), {
            'valuation': {
              'account_id': 'acct_1',
              'amount': '1234.5',
              'date': '2026-11-10',
              'notes': 'Statement',
            },
          });
          return http.Response(
            '{"id":"val_1","date":"2026-11-10","amount":"\$1,234.50",'
            '"currency":"USD","notes":"Statement","kind":"reconciliation",'
            '"account":{"id":"acct_1","name":"Savings","account_type":"depository"},'
            '"created_at":"2026-11-10T12:00:00Z","updated_at":"2026-11-10T12:00:00Z"}',
            201,
          );
        }),
      );

      final result = await service.createValuation(
        accessToken: 'token',
        accountId: 'acct_1',
        amount: '1234.5',
        date: '2026-11-10',
        notes: '  Statement ',
      );

      expect(result['success'], true);
      expect(result['valuation']['amount'], r'$1,234.50');
    });

    test('omits a blank note', () async {
      final service = ValuationsService(
        client: MockClient((request) async {
          final valuation = jsonDecode(request.body)['valuation'] as Map;
          expect(valuation.containsKey('notes'), false);
          return http.Response('{"id":"val_1"}', 201);
        }),
      );

      final result = await service.createValuation(
        accessToken: 'token',
        accountId: 'acct_1',
        amount: '10',
        date: '2026-11-10',
        notes: '   ',
      );
      expect(result['success'], true);
    });

    test('returns the server validation message', () async {
      final service = ValuationsService(
        client: MockClient((_) async => http.Response(
              '{"error":"validation_failed","message":"Valuation could not be created",'
              '"errors":["Date is in the future"]}',
              422,
            )),
      );

      final result = await service.createValuation(
        accessToken: 'token',
        accountId: 'acct_1',
        amount: '10',
        date: '2026-11-10',
      );
      expect(result['success'], false);
      expect(result['error'],
          'Valuation could not be created: Date is in the future');
    });

    test('returns unauthorized on 401', () async {
      final service = ValuationsService(
        client: MockClient(
            (_) async => http.Response('{"error":"unauthorized"}', 401)),
      );

      final result = await service.createValuation(
        accessToken: 'token',
        accountId: 'acct_1',
        amount: '10',
        date: '2026-11-10',
      );
      expect(result, {'success': false, 'error': 'unauthorized'});
    });
  });
}
