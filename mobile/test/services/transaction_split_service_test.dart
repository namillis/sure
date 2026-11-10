import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/transaction_split.dart';
import 'package:sure_mobile/services/transaction_split_service.dart';

const _splitJson = '''
{
  "transaction_id": "txn_1",
  "amount": "\$100.00",
  "amount_decimal": "100.0",
  "amount_cents": 10000,
  "currency": "USD",
  "children": [
    {
      "id": "child_1", "date": "2026-11-01", "amount": "\$60.00",
      "amount_decimal": "60.0", "currency": "USD", "name": "Groceries",
      "classification": "expense", "excluded": false, "split_parent": false,
      "account": {"id": "acct_1", "name": "Checking", "account_type": "depository"},
      "category": {"id": "cat_food", "name": "Food", "color": "#000", "icon": "apple"},
      "merchant": {"id": "m_1", "name": "Shop"},
      "tags": [{"id": "tag_1", "name": "Home", "color": "#fff"}]
    },
    {
      "id": "child_2", "date": "2026-11-01", "amount": "\$40.00",
      "amount_decimal": "40.0", "currency": "USD", "name": "Household",
      "classification": "expense", "excluded": true, "split_parent": false,
      "account": {"id": "acct_1", "name": "Checking", "account_type": "depository"},
      "category": null, "merchant": null, "tags": []
    }
  ]
}
''';

void main() {
  group('TransactionSplitService', () {
    test('getSplit reads the parent total and children', () async {
      final service = TransactionSplitService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/transactions/txn_1/split');
          expect(request.headers['Authorization'], 'Bearer token');
          return http.Response(_splitJson, 200);
        }),
      );

      final result =
          await service.getSplit(accessToken: 'token', transactionId: 'txn_1');

      expect(result['success'], true);
      final split = result['split'] as TransactionSplit;
      expect(split.amountDecimal, '100.0');
      expect(split.currency, 'USD');
      expect(split.children, hasLength(2));
      expect(split.children.first.categoryId, 'cat_food');
      expect(split.children.first.tagIds, ['tag_1']);
      expect(split.children.last.excluded, true);
    });

    test('getSplit marks a 404 as not split', () async {
      final service = TransactionSplitService(
        client: MockClient((_) async => http.Response(
              '{"error":"not_found","message":"Transaction is not split"}',
              404,
            )),
      );

      final result =
          await service.getSplit(accessToken: 'token', transactionId: 'txn_1');

      expect(result['success'], false);
      expect(result['notSplit'], true);
      expect(result['error'], 'Transaction is not split');
    });

    test('createSplit posts the parts in the API shape', () async {
      final service = TransactionSplitService(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/transactions/txn_1/split');
          expect(request.headers['Content-Type'], startsWith('application/json'));
          expect(jsonDecode(request.body), {
            'split': {
              'splits': [
                {'amount': '60', 'name': 'Groceries', 'category_id': 'cat_food'},
                {'amount': '40.5'},
              ],
            },
          });
          return http.Response(_splitJson, 201);
        }),
      );

      final result = await service.createSplit(
        accessToken: 'token',
        transactionId: 'txn_1',
        parts: const [
          SplitPart(amount: '60', name: ' Groceries ', categoryId: 'cat_food'),
          SplitPart(amount: '40.5', name: '  '),
        ],
      );

      expect(result['success'], true);
      expect(result['split'], isA<TransactionSplit>());
    });

    test('updateSplit patches every part, carrying merchant, tags and exclusion',
        () async {
      final service = TransactionSplitService(
        client: MockClient((request) async {
          expect(request.method, 'PATCH');
          expect(request.url.path, '/api/v1/transactions/txn_1/split');
          expect(jsonDecode(request.body), {
            'split': {
              'splits': [
                {
                  'amount': '-60',
                  'merchant_id': 'm_1',
                  'tag_ids': ['tag_1'],
                  'excluded': false,
                },
                {'amount': '-40', 'tag_ids': [], 'excluded': true},
              ],
            },
          });
          return http.Response(_splitJson, 200);
        }),
      );

      final result = await service.updateSplit(
        accessToken: 'token',
        transactionId: 'txn_1',
        parts: const [
          SplitPart(
            amount: '-60',
            merchantId: 'm_1',
            tagIds: ['tag_1'],
            excluded: false,
          ),
          SplitPart(amount: '-40', tagIds: [], excluded: true),
        ],
      );

      expect(result['success'], true);
    });

    test('deleteSplit sends DELETE and accepts 204', () async {
      final service = TransactionSplitService(
        client: MockClient((request) async {
          expect(request.method, 'DELETE');
          expect(request.url.path, '/api/v1/transactions/txn%2F1/split');
          return http.Response('', 204);
        }),
      );

      final result = await service.deleteSplit(
        accessToken: 'token',
        transactionId: 'txn/1',
      );

      expect(result, {'success': true});
    });

    test('surfaces the validation reason from a 422', () async {
      final service = TransactionSplitService(
        client: MockClient((_) async => http.Response(
              '{"error":"validation_failed","message":"Transaction cannot be split",'
              '"errors":["Transaction is pending"]}',
              422,
            )),
      );

      final result = await service.createSplit(
        accessToken: 'token',
        transactionId: 'txn_1',
        parts: const [SplitPart(amount: '1')],
      );

      expect(result['success'], false);
      expect(result['error'], 'Transaction cannot be split: Transaction is pending');
    });

    test('does not repeat a message that is also the only error', () async {
      final service = TransactionSplitService(
        client: MockClient((_) async => http.Response(
              '{"error":"validation_failed","message":"splits must be a non-empty array",'
              '"errors":["splits must be a non-empty array"]}',
              422,
            )),
      );

      final result = await service.updateSplit(
        accessToken: 'token',
        transactionId: 'txn_1',
        parts: const [],
      );

      expect(result['error'], 'splits must be a non-empty array');
    });

    test('returns unauthorized on 401', () async {
      final service = TransactionSplitService(
        client: MockClient((_) async => http.Response('{"error":"unauthorized"}', 401)),
      );

      final result = await service.deleteSplit(
        accessToken: 'token',
        transactionId: 'txn_1',
      );

      expect(result['success'], false);
      expect(result['error'], 'unauthorized');
    });
  });
}
