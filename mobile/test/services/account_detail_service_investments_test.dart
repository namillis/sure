import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/account_trade.dart';
import 'package:sure_mobile/services/account_detail_service.dart';

String _balance(String id, String date, int cents) =>
    '{"id":"$id","date":"$date","currency":"USD",'
    '"balance":"\$${cents ~/ 100}.00","balance_cents":$cents}';

String _holding(String id, String date, String ticker, String amount,
        {String? avgCost}) =>
    '{"id":"$id","date":"$date","qty":"2.0","price":"\$10.00",'
    '"amount":"$amount","currency":"USD",'
    '"avg_cost":${avgCost == null ? 'null' : '"$avgCost"'},'
    '"security":{"id":"sec_$ticker","ticker":"$ticker","name":"$ticker Inc."}}';

void main() {
  group('AccountDetailService.getBalanceHistory', () {
    test('walks every page, passes start_date and returns oldest first',
        () async {
      final requestedPages = <String>[];
      final service = AccountDetailService(
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/balances');
          expect(request.url.queryParameters['account_id'], 'acct_1');
          expect(request.url.queryParameters['per_page'], '100');
          expect(request.url.queryParameters['start_date'], '2026-10-11');
          final page = request.url.queryParameters['page']!;
          requestedPages.add(page);

          // Newest first, as the API orders them.
          final body = page == '1'
              ? '[${_balance('b3', '2026-11-10', 30000)},'
                  '${_balance('b2', '2026-11-09', 20000)}]'
              : '[${_balance('b1', '2026-11-08', 10000)}]';
          return http.Response(
            '{"balances":$body,"pagination":{"page":$page,"total_pages":2}}',
            200,
          );
        }),
      );

      final result = await service.getBalanceHistory(
        accessToken: 'token',
        accountId: 'acct_1',
        startDate: DateTime(2026, 10, 11),
      );

      expect(result['success'], true);
      expect(requestedPages, ['1', '2']);
      expect(
        (result['balances'] as List).map((b) => b.id),
        ['b1', 'b2', 'b3'],
      );
    });

    test('omits start_date for full history and caps pages', () async {
      var requests = 0;
      final service = AccountDetailService(
        client: MockClient((request) async {
          requests += 1;
          expect(request.url.queryParameters.containsKey('start_date'), false);
          return http.Response(
            '{"balances":[${_balance('b$requests', '2026-11-0$requests', 100)}],'
            '"pagination":{"total_pages":99}}',
            200,
          );
        }),
      );

      final result = await service.getBalanceHistory(
        accessToken: 'token',
        accountId: 'acct_1',
        maxPages: 3,
      );

      expect(result['success'], true);
      expect(requests, 3);
    });

    test('reports unauthorized when any page returns 401', () async {
      final service = AccountDetailService(
        client: MockClient((request) async => http.Response('{}', 401)),
      );

      final result = await service.getBalanceHistory(
        accessToken: 'token',
        accountId: 'acct_1',
      );

      expect(result, {'success': false, 'error': 'unauthorized'});
    });
  });

  group('AccountDetailService.getCurrentHoldings', () {
    test('returns every position on the latest date, largest first',
        () async {
      final service = AccountDetailService(
        client: MockClient((request) async {
          final holdings = [
            _holding('old', '2026-11-09', 'OLD', r'$999.00'),
            for (var i = 1; i <= 7; i++)
              _holding('h$i', '2026-11-10', 'T$i', '\$${i * 10}.00',
                  avgCost: r'$5.00'),
          ].join(',');
          return http.Response(
            '{"holdings":[$holdings],"pagination":{"total_pages":1}}',
            200,
          );
        }),
      );

      final result = await service.getCurrentHoldings(
        accessToken: 'token',
        accountId: 'acct_1',
      );

      expect(result['success'], true);
      final holdings = result['holdings'] as List;
      expect(holdings, hasLength(7));
      expect(holdings.first.ticker, 'T7');
      expect(holdings.first.avgCost, r'$5.00');
      expect(holdings.first.securityId, 'sec_T7');
    });
  });

  group('AccountDetailService.getTrades', () {
    test('parses a page of trades and reports whether more exist', () async {
      final service = AccountDetailService(
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/trades');
          expect(request.url.queryParameters['account_id'], 'acct_1');
          expect(request.url.queryParameters['page'], '2');
          return http.Response(
            '{"trades":[{"id":"t1","date":"2026-11-03","name":"Buy VTI",'
            '"amount":"\$1,450.00","currency":"USD","qty":"5.0",'
            '"price":"\$290.00","investment_activity_label":"Buy",'
            '"security":{"id":"s1","ticker":"VTI","name":"Vanguard Total"}}],'
            '"pagination":{"page":2,"total_pages":3}}',
            200,
          );
        }),
      );

      final result = await service.getTrades(
        accessToken: 'token',
        accountId: 'acct_1',
        page: 2,
      );

      expect(result['success'], true);
      expect(result['hasMore'], true);
      final trade = (result['trades'] as List).single as AccountTrade;
      expect(trade.ticker, 'VTI');
      expect(trade.activityLabel, 'Buy');
      expect(trade.quantity, '5.0');
    });

    test('queries several accounts with repeated account_ids[] keys',
        () async {
      final service = AccountDetailService(
        client: MockClient((request) async {
          expect(request.url.queryParametersAll['account_ids[]'], ['a1', 'a2']);
          expect(request.url.queryParameters.containsKey('account_id'), false);
          expect(request.url.queryParameters['per_page'], '10');
          return http.Response(
            '{"trades":[{"id":"t1","date":"2026-11-03","name":"Buy VTI",'
            '"amount":"\$10.00","currency":"USD","qty":"1","price":"\$10.00",'
            '"account":{"id":"a2","name":"Roth IRA"},"security":null}],'
            '"pagination":{"page":1,"total_pages":1}}',
            200,
          );
        }),
      );

      final result = await service.getTrades(
        accessToken: 'token',
        accountIds: ['a1', 'a2'],
        perPage: 10,
      );

      final trade = (result['trades'] as List).single as AccountTrade;
      expect(trade.accountId, 'a2');
      expect(trade.accountName, 'Roth IRA');
    });

    test('handles trades without a security', () async {
      final service = AccountDetailService(
        client: MockClient((request) async => http.Response(
              '{"trades":[{"id":"t2","date":"2026-11-01","name":"Dividend",'
              '"amount":"\$12.00","currency":"USD","qty":"0","price":"\$0.00",'
              '"security":null}],"pagination":{"page":1,"total_pages":1}}',
              200,
            )),
      );

      final result = await service.getTrades(
        accessToken: 'token',
        accountId: 'acct_1',
      );

      expect(result['hasMore'], false);
      final trade = (result['trades'] as List).single as AccountTrade;
      expect(trade.ticker, isNull);
      expect(trade.name, 'Dividend');
    });
  });
}
