import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/recurring_transaction.dart';
import 'package:sure_mobile/services/recurring_transactions_service.dart';

import '../support/recurring_fixtures.dart';

void main() {
  group('RecurringTransactionsService', () {
    test('getAll walks every page and parses rows', () async {
      final pages = <String>[];
      final service = RecurringTransactionsService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/recurring_transactions');
          expect(request.url.queryParameters['per_page'], '100');
          expect(request.headers['Authorization'], 'Bearer token');
          final page = request.url.queryParameters['page']!;
          pages.add(page);
          return http.Response(
            page == '1'
                ? recurringIndexBody([
                    recurringJson(categoryId: 'cat_gym', rules: [
                      {'frequency': 'weekly', 'interval': 2},
                    ]),
                  ], totalPages: 2)
                : recurringIndexBody([
                    recurringJson(
                      id: 'rt_2',
                      name: null,
                      merchant: {'id': 'm1', 'name': 'Netflix'},
                      account: null,
                      amountCents: -250000,
                      amount: r'-$2,500.00',
                      status: 'inactive',
                    ),
                  ], page: 2, totalPages: 2),
            200,
          );
        }),
      );

      final result = await service.getAll(accessToken: 'token');

      expect(result['success'], true);
      expect(pages, ['1', '2']);
      final items =
          (result['recurring_transactions'] as List).cast<RecurringTransaction>();
      expect(items, hasLength(2));
      expect(items[0].displayName, 'Gym Membership');
      expect(items[0].accountName, 'Checking');
      expect(items[0].categoryId, 'cat_gym');
      expect(items[1].categoryId, isNull);
      expect(items[0].nextExpectedDate, DateTime(2026, 11, 20));
      expect(items[0].primaryRule!.frequency, 'weekly');
      expect(items[0].primaryRule!.interval, 2);
      expect(items[1].displayName, 'Netflix');
      expect(items[1].accountId, isNull);
      expect(items[1].isInflow, true);
      expect(items[1].isActive, false);
    });

    test('getAll returns unauthorized on 401', () async {
      final service = RecurringTransactionsService(
        client: MockClient((_) async => http.Response('{}', 401)),
      );
      final result = await service.getAll(accessToken: 'token');
      expect(result, {'success': false, 'error': 'unauthorized'});
    });

    test('create posts the attributes wrapped in recurring_transaction',
        () async {
      final service = RecurringTransactionsService(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/recurring_transactions');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['recurring_transaction'], {
            'name': 'Gym Membership',
            'amount': 49.99,
            'currency': 'USD',
            'next_expected_date': '2026-11-20',
          });
          return http.Response(jsonEncode(recurringJson()), 201);
        }),
      );

      final result = await service.create(accessToken: 'token', attributes: {
        'name': 'Gym Membership',
        'amount': 49.99,
        'currency': 'USD',
        'next_expected_date': '2026-11-20',
      });

      expect(result['success'], true);
      expect((result['recurring_transaction'] as RecurringTransaction).id, 'rt_1');
    });

    test('create surfaces validation messages from a 422', () async {
      final service = RecurringTransactionsService(
        client: MockClient((_) async => http.Response(
              jsonEncode({
                'error': 'validation_failed',
                'message': 'Recurring transaction could not be created',
                'errors': ['Next expected date can\'t be blank'],
              }),
              422,
            )),
      );
      final result =
          await service.create(accessToken: 'token', attributes: const {});
      expect(result['success'], false);
      expect(result['error'], 'Next expected date can\'t be blank');
    });

    test('update patches the member path with only the given fields',
        () async {
      final service = RecurringTransactionsService(
        client: MockClient((request) async {
          expect(request.method, 'PATCH');
          expect(request.url.path, '/api/v1/recurring_transactions/rt%2F1');
          expect(jsonDecode(request.body), {
            'recurring_transaction': {'status': 'inactive'},
          });
          return http.Response(
              jsonEncode(recurringJson(id: 'rt/1', status: 'inactive')), 200);
        }),
      );
      final result = await service.update(
          accessToken: 'token', id: 'rt/1', attributes: {'status': 'inactive'});
      expect(result['success'], true);
      expect(
          (result['recurring_transaction'] as RecurringTransaction).status,
          'inactive');
    });

    test('update returns unauthorized on 401', () async {
      final service = RecurringTransactionsService(
        client: MockClient((_) async => http.Response('{}', 401)),
      );
      final result = await service.update(
          accessToken: 'token', id: 'rt_1', attributes: const {});
      expect(result['error'], 'unauthorized');
    });

    test('delete sends DELETE to the member path', () async {
      final service = RecurringTransactionsService(
        client: MockClient((request) async {
          expect(request.method, 'DELETE');
          expect(request.url.path, '/api/v1/recurring_transactions/rt_1');
          return http.Response(
              '{"message":"Recurring transaction deleted successfully"}', 200);
        }),
      );
      expect(await service.delete(accessToken: 'token', id: 'rt_1'),
          {'success': true});
    });

    test('delete returns unauthorized on 401', () async {
      final service = RecurringTransactionsService(
        client: MockClient((_) async => http.Response('{}', 401)),
      );
      final result = await service.delete(accessToken: 'token', id: 'rt_1');
      expect(result['error'], 'unauthorized');
    });
  });
}
