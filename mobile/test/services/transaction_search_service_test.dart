import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/activity_filters.dart';
import 'package:sure_mobile/models/activity_transaction.dart';
import 'package:sure_mobile/services/transaction_search_service.dart';

/// A row shaped like app/views/api/v1/transactions/_transaction.json.jbuilder.
const _row = {
  'id': 'txn_1',
  'entry_id': 'entry_1',
  'date': '2026-11-09',
  'amount': r'$12.50',
  'amount_cents': 1250,
  'signed_amount_cents': -1250,
  'amount_decimal': '12.5',
  'currency': 'USD',
  'name': 'Blue Bottle',
  'notes': null,
  'classification': 'expense',
  'kind': 'standard',
  'excluded': false,
  'split_parent': true,
  'account': {
    'id': 'acct_1',
    'name': 'Everyday Checking',
    'account_type': 'depository',
  },
  'category': {
    'id': 'cat_1',
    'name': 'Coffee',
    'color': '#e99537',
    'icon': 'coffee',
  },
  'merchant': {'id': 'm_1', 'name': 'Blue Bottle Coffee'},
  'tags': [
    {'id': 'tag_1', 'name': 'Work', 'color': '#123456'},
  ],
  'transfer': {
    'id': 'tr_1',
    'amount': r'$12.50',
    'currency': 'USD',
    'other_account': {
      'id': 'acct_2',
      'name': 'Savings',
      'account_type': 'depository',
    },
  },
  'created_at': '2026-11-09T10:00:00Z',
  'updated_at': '2026-11-09T10:00:00Z',
};

String _indexBody({int page = 1, int pages = 3, int count = 120}) =>
    jsonEncode({
      'transactions': [_row],
      'pagination': {
        'page': page,
        'per_page': 50,
        'total_count': count,
        'total_pages': pages,
      },
    });

void main() {
  final now = DateTime(2026, 11, 10, 16, 0);

  Future<Uri> captureSearch(ActivityFilters filters,
      {int page = 1, int perPage = 50}) async {
    late Uri captured;
    final service = TransactionSearchService(
      client: MockClient((request) async {
        captured = request.url;
        return http.Response(_indexBody(), 200);
      }),
    );
    await service.search(
      accessToken: 'token',
      filters: filters,
      page: page,
      perPage: perPage,
      now: now,
    );
    return captured;
  }

  group('TransactionSearchService.search query', () {
    test('defaults to this month, page 1 of 50', () async {
      final url = await captureSearch(const ActivityFilters());
      expect(url.path, '/api/v1/transactions');
      expect(url.queryParameters, {
        'start_date': '2026-11-01',
        'end_date': '2026-11-30',
        'page': '1',
        'per_page': '50',
      });
    });

    test('sends a trimmed search term', () async {
      final url = await captureSearch(
        const ActivityFilters(
            search: '  coffee ', datePreset: ActivityDatePreset.all),
      );
      expect(url.queryParameters['search'], 'coffee');
      expect(url.queryParameters.containsKey('start_date'), isFalse);
      expect(url.queryParameters.containsKey('end_date'), isFalse);
    });

    test('sends accounts, categories and tags as Rails array params', () async {
      final url = await captureSearch(
        const ActivityFilters(
          accountIds: {'acct_2', 'acct_1'},
          categoryIds: {'cat_1'},
          tagIds: {'tag_1', 'tag_2'},
        ),
      );
      expect(url.queryParametersAll['account_ids[]'], ['acct_1', 'acct_2']);
      expect(url.queryParametersAll['category_ids[]'], ['cat_1']);
      expect(url.queryParametersAll['tag_ids[]'], ['tag_1', 'tag_2']);
    });

    test('sends the income or expense type', () async {
      final income = await captureSearch(
        const ActivityFilters(type: ActivityTypeFilter.income),
      );
      expect(income.queryParameters['type'], 'income');
      final expense = await captureSearch(
        const ActivityFilters(type: ActivityTypeFilter.expense),
      );
      expect(expense.queryParameters['type'], 'expense');
    });

    test('sends a custom date range', () async {
      final url = await captureSearch(
        ActivityFilters(
          datePreset: ActivityDatePreset.custom,
          customStart: DateTime(2026, 2, 3),
          customEnd: DateTime(2026, 3, 4),
        ),
      );
      expect(url.queryParameters['start_date'], '2026-02-03');
      expect(url.queryParameters['end_date'], '2026-03-04');
    });

    test('asks for the requested page and caps per_page at 100', () async {
      final url = await captureSearch(
        const ActivityFilters(),
        page: 3,
        perPage: 500,
      );
      expect(url.queryParameters['page'], '3');
      expect(url.queryParameters['per_page'], '100');
    });
  });

  group('TransactionSearchService.search response', () {
    test('parses rows and pagination', () async {
      final service = TransactionSearchService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.headers['Authorization'], 'Bearer token');
          return http.Response(_indexBody(page: 2, pages: 3, count: 120), 200);
        }),
      );

      final result = await service.search(
        accessToken: 'token',
        filters: const ActivityFilters(),
        page: 2,
        now: now,
      );

      expect(result['success'], true);
      expect(result['page'], 2);
      expect(result['totalPages'], 3);
      expect(result['totalCount'], 120);
      final rows = result['transactions'] as List<ActivityTransaction>;
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.id, 'txn_1');
      expect(row.transaction.name, 'Blue Bottle');
      expect(row.transaction.amount, r'$12.50');
      expect(row.transaction.accountId, 'acct_1');
      expect(row.transaction.categoryName, 'Coffee');
      expect(row.transaction.merchantName, 'Blue Bottle Coffee');
      expect(row.transaction.tagNames, ['Work']);
      expect(row.accountName, 'Everyday Checking');
      expect(row.accountType, 'depository');
      expect(row.categoryColor, '#e99537');
      expect(row.isSplitParent, isTrue);
      expect(row.isTransfer, isTrue);
      expect(row.transferAccountName, 'Savings');
      expect(row.date, DateTime(2026, 11, 9));
    });

    test('a row without category, transfer or split reads as plain', () {
      final row = ActivityTransaction.fromJson({
        ..._row,
        'category': null,
        'transfer': null,
        'split_parent': false,
      });
      expect(row.transaction.categoryName, isNull);
      expect(row.categoryColor, isNull);
      expect(row.isTransfer, isFalse);
      expect(row.transferAccountName, isNull);
      expect(row.isSplitParent, isFalse);
    });

    test('returns unauthorized on 401', () async {
      final service = TransactionSearchService(
        client: MockClient(
          (_) async => http.Response('{"error":"unauthorized"}', 401),
        ),
      );
      final result = await service.search(
        accessToken: 'token',
        filters: const ActivityFilters(),
      );
      expect(result['success'], false);
      expect(result['error'], 'unauthorized');
    });

    test('returns a failure on a server error', () async {
      final service = TransactionSearchService(
        client: MockClient((_) async => http.Response('oops', 500)),
      );
      final result = await service.search(
        accessToken: 'token',
        filters: const ActivityFilters(),
      );
      expect(result['success'], false);
      expect(result['error'], 'Failed to load transactions');
    });
  });

  group('TransactionSearchService.updateCategory', () {
    test('patches only the category and parses the updated row', () async {
      final service = TransactionSearchService(
        client: MockClient((request) async {
          expect(request.method, 'PATCH');
          expect(request.url.path, '/api/v1/transactions/txn_1');
          expect(request.headers['Authorization'], 'Bearer token');
          expect(jsonDecode(request.body), {
            'transaction': {'category_id': 'cat_2'},
          });
          return http.Response(
            jsonEncode({
              ..._row,
              'category': {'id': 'cat_2', 'name': 'Food', 'color': '#00ff00'},
            }),
            200,
          );
        }),
      );

      final result = await service.updateCategory(
        accessToken: 'token',
        transactionId: 'txn_1',
        categoryId: 'cat_2',
      );

      expect(result['success'], true);
      final row = result['transaction'] as ActivityTransaction;
      expect(row.transaction.categoryId, 'cat_2');
      expect(row.categoryColor, '#00ff00');
    });

    test('returns the server message on a validation failure', () async {
      final service = TransactionSearchService(
        client: MockClient(
          (_) async => http.Response(
            '{"error":"validation_failed","message":"Split child transactions cannot be edited directly."}',
            422,
          ),
        ),
      );
      final result = await service.updateCategory(
        accessToken: 'token',
        transactionId: 'txn_1',
        categoryId: 'cat_2',
      );
      expect(result['success'], false);
      expect(result['error'], contains('Split child'));
    });

    test('returns unauthorized on 401', () async {
      final service = TransactionSearchService(
        client: MockClient((_) async => http.Response('', 401)),
      );
      final result = await service.updateCategory(
        accessToken: 'token',
        transactionId: 'txn_1',
        categoryId: 'cat_2',
      );
      expect(result['success'], false);
      expect(result['error'], 'unauthorized');
    });
  });
}
