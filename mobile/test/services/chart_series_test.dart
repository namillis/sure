import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/account.dart';
import 'package:sure_mobile/services/account_detail_service.dart';
import 'package:sure_mobile/services/net_worth_history_service.dart';
import 'package:sure_mobile/utils/net_worth_history.dart';

import '../support/memory_cache.dart';

String _series({String currency = 'USD', String? accountId}) => jsonEncode({
      'period': 'all_time',
      'start_date': '2025-01-01',
      'end_date': '2025-01-15',
      'interval': '1 week',
      'currency': currency,
      if (accountId != null) 'account_id': accountId,
      'trend': null,
      'values': [
        {'date': '2025-01-01', 'value': r'$100.00', 'value_cents': 10000},
        {'date': '2025-01-08', 'value': r'$150.00', 'value_cents': 15000},
        {'date': '2025-01-15', 'value': r'$175.00', 'value_cents': 17500},
      ],
    });

final _accounts = [
  Account(
    id: 'a1',
    name: 'Checking',
    balance: '1',
    balanceCents: 100,
    currency: 'USD',
    classification: 'asset',
    accountType: 'depository',
  ),
  Account(
    id: 'uk',
    name: 'UK',
    balance: '1',
    balanceCents: 100,
    currency: 'GBP',
    classification: 'asset',
    accountType: 'depository',
  ),
];

void main() {
  group('net worth from charts.series', () {
    test('one request, weekly points, no separate other currencies', () async {
      final requests = <http.Request>[];
      final service = NetWorthHistoryService(
        accountDetailService: AccountDetailService(
          client: MockClient((r) async {
            requests.add(r);
            return http.Response(_series(), 200, headers: {'etag': 'W/"1"'});
          }),
        ),
      );
      final result = await service.load(
        accessToken: 'token',
        accounts: _accounts,
        mainCurrency: 'USD',
        start: null,
        end: DateTime(2025, 1, 15),
        useServerSeries: true,
      );
      expect(requests.single.url.path, '/api/v1/net_worth_series');
      expect(requests.single.url.queryParameters, {'period': 'all_time'});
      final history = result['history'] as NetWorthHistory;
      expect(history.points.map((p) => p.cents), [10000, 15000, 17500]);
      expect(history.points[1].date, DateTime(2025, 1, 8));
      expect(history.otherCurrencies, isEmpty);
      expect(history.changeCents, 7500);
    });

    test('a window sends start and end dates', () async {
      late Uri url;
      final service = NetWorthHistoryService(
        accountDetailService: AccountDetailService(
          client: MockClient((r) async {
            url = r.url;
            return http.Response(_series(), 200);
          }),
        ),
      );
      await service.load(
        accessToken: 'token',
        accounts: _accounts,
        mainCurrency: 'USD',
        start: DateTime(2024, 11, 13),
        end: DateTime(2025, 11, 13),
        useServerSeries: true,
      );
      expect(url.queryParameters,
          {'start_date': '2024-11-13', 'end_date': '2025-11-13'});
    });

    test('the saved chart is revalidated with its ETag; 304 reuses it',
        () async {
      final cache = MemoryCache();
      final etags = <String?>[];
      var status = 200;
      final service = NetWorthHistoryService(
        cache: cache,
        accountDetailService: AccountDetailService(
          client: MockClient((r) async {
            etags.add(r.headers['If-None-Match']);
            if (status == 304) return http.Response('', 304);
            return http.Response(_series(), 200, headers: {'etag': 'W/"7"'});
          }),
        ),
      );
      Future<Map<String, dynamic>> load() => service.load(
            accessToken: 'token',
            accounts: _accounts,
            mainCurrency: 'USD',
            start: null,
            end: DateTime(2025, 1, 15),
            cacheKey: NetWorthHistoryService.cacheKey('all'),
            useServerSeries: true,
          );
      await load();
      status = 304;
      final again = await load();
      expect(etags, [null, 'W/"7"']);
      expect((again['history'] as NetWorthHistory).points.length, 3);

      final saved =
          await service.cached(NetWorthHistoryService.cacheKey('all'));
      expect(saved!.etag, 'W/"7"');
      expect(saved.history.points[2].date, DateTime(2025, 1, 15));
    });

    test('401 is unauthorized', () async {
      final service = NetWorthHistoryService(
        accountDetailService: AccountDetailService(
          client: MockClient((_) async => http.Response('{}', 401)),
        ),
      );
      final result = await service.load(
        accessToken: 'token',
        accounts: _accounts,
        mainCurrency: 'USD',
        start: null,
        end: DateTime(2025, 1, 15),
        useServerSeries: true,
      );
      expect(result['error'], 'unauthorized');
    });
  });

  test('an account chart is one balance_series request', () async {
    late Uri url;
    final service = AccountDetailService(
      client: MockClient((r) async {
        url = r.url;
        return http.Response(_series(accountId: 'a1'), 200);
      }),
    );
    final result = await service.getBalanceHistory(
      accessToken: 'token',
      accountId: 'a1',
      useSeries: true,
    );
    expect(url.path, '/api/v1/accounts/a1/balance_series');
    expect(url.queryParameters, {'period': 'all_time'});
    final rows = (result['balances'] as List).cast<dynamic>();
    expect(rows.map((b) => b.balanceCents), [10000, 15000, 17500]);
    expect(rows.first.currency, 'USD');
  });

  test('older consecutive-day saved charts still read', () {
    final h = NetWorthHistory.fromJson({
      'v': 1,
      'start': '2026-10-30',
      'cents': [1, 2, 3],
      'other': [],
    })!;
    expect(h.points.last.date, DateTime(2026, 11, 1));
  });
}
