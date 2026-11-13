import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/services/account_detail_service.dart';

void main() {
  group('AccountDetailService', () {
    test('fetches account metadata from the account show endpoint', () async {
      final service = AccountDetailService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/accounts/acct_1');
          expect(request.headers['Authorization'], 'Bearer token');
          return http.Response(
            '{"id":"acct_1","name":"Brokerage","balance":"\$1,200.00",'
            '"balance_cents":120000,"cash_balance":"\$200.00",'
            '"cash_balance_cents":20000,"currency":"USD",'
            '"classification":"asset","account_type":"investment",'
            '"subtype":"brokerage","status":"active",'
            '"institution_name":"Sure Bank",'
            '"institution_domain":"sure.local",'
            '"created_at":"2026-06-01T00:00:00Z",'
            '"updated_at":"2026-06-02T00:00:00Z"}',
            200,
          );
        }),
      );

      final result = await service.getAccountDetail(
        accessToken: 'token',
        accountId: 'acct_1',
      );

      expect(result['success'], true);
      expect(result['account'].cashBalance, r'$200.00');
      expect(result['account'].institutionName, 'Sure Bank');
    });

    test('returns unauthorized for account detail 401 responses', () async {
      final service = AccountDetailService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/accounts/acct_1');
          expect(request.headers['Authorization'], 'Bearer token');
          return http.Response('{"error":"Unauthorized"}', 401);
        }),
      );

      final result = await service.getAccountDetail(
        accessToken: 'token',
        accountId: 'acct_1',
      );

      expect(result['success'], false);
      expect(result['error'], 'unauthorized');
    });

    test('encodes account ids in account detail paths', () async {
      final service = AccountDetailService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.toString(), contains('/api/v1/accounts/acct%2F1'));
          return http.Response(
            '{"id":"acct/1","name":"Brokerage","balance":"\$1,200.00",'
            '"currency":"USD","classification":"asset",'
            '"account_type":"investment"}',
            200,
          );
        }),
      );

      final result = await service.getAccountDetail(
        accessToken: 'token',
        accountId: 'acct/1',
      );

      expect(result['success'], true);
      expect(result['account'].id, 'acct/1');
    });

    test('returns fallback error for account detail 404 responses', () async {
      final service = AccountDetailService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/accounts/missing');
          return http.Response('{"error":"Not found"}', 404);
        }),
      );

      final result = await service.getAccountDetail(
        accessToken: 'token',
        accountId: 'missing',
      );

      expect(result['success'], false);
      expect(result['error'], 'Failed to fetch account');
    });

    test('returns fallback error for account detail server failures', () async {
      final service = AccountDetailService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/accounts/acct_1');
          return http.Response('{"error":"Server error"}', 500);
        }),
      );

      final result = await service.getAccountDetail(
        accessToken: 'token',
        accountId: 'acct_1',
      );

      expect(result['success'], false);
      expect(result['error'], 'Failed to fetch account');
    });

    test('returns generic error for account detail network failures', () async {
      final service = AccountDetailService(
        client: MockClient((request) async {
          throw http.ClientException('connection failed');
        }),
      );

      final result = await service.getAccountDetail(
        accessToken: 'token',
        accountId: 'acct_1',
      );

      expect(result['success'], false);
      expect(
        result['error'],
        'Unable to load account details. Please try again later.',
      );
    });

    test('returns generic error for malformed account detail JSON', () async {
      final service = AccountDetailService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/accounts/acct_1');
          return http.Response('{', 200);
        }),
      );

      final result = await service.getAccountDetail(
        accessToken: 'token',
        accountId: 'acct_1',
      );

      expect(result['success'], false);
      expect(
        result['error'],
        'Unable to load account details. Please try again later.',
      );
    });

    test('fetches scoped balance history', () async {
      final service = AccountDetailService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/balances');
          expect(request.url.queryParameters['account_id'], 'acct_1');
          expect(request.url.queryParameters['per_page'], '30');
          return http.Response(
            '{"balances":[{"id":"bal_1","date":"2026-06-01",'
            '"currency":"USD","balance":"\$1,200.00",'
            '"balance_cents":120000,"cash_balance":"\$200.00",'
            '"cash_balance_cents":20000}]}',
            200,
          );
        }),
      );

      final result = await service.getBalances(
        accessToken: 'token',
        accountId: 'acct_1',
      );

      expect(result['success'], true);
      expect(result['balances'].single.balanceCents, 120000);
    });

    test('returns generic error for malformed balance dates', () async {
      final service = AccountDetailService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/balances');
          return http.Response(
            '{"balances":[{"id":"bal_1","date":"not-a-date",'
            '"currency":"USD","balance":"\$1,200.00"}]}',
            200,
          );
        }),
      );

      final result = await service.getBalances(
        accessToken: 'token',
        accountId: 'acct_1',
      );

      expect(result['success'], false);
      expect(
        result['error'],
        'Unable to load balance history. Please try again later.',
      );
    });

    test('fetches scoped holdings for investment accounts', () async {
      final service = AccountDetailService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/holdings');
          expect(request.url.queryParameters['account_id'], 'acct_1');
          expect(request.url.queryParameters['page'], '1');
          expect(request.url.queryParameters['per_page'], '100');
          return http.Response(
            '{"holdings":[{"id":"holding_1","date":"2026-06-01",'
            '"qty":"4.0","price":"\$10.00","amount":"\$40.00",'
            '"currency":"USD","security":{"ticker":"SURE",'
            '"name":"Sure Inc."}}],'
            '"pagination":{"page":1,"per_page":100,"total_count":1,'
            '"total_pages":1}}',
            200,
          );
        }),
      );

      final result = await service.getHoldings(
        accessToken: 'token',
        accountId: 'acct_1',
      );

      expect(result['success'], true);
      expect(result['holdings'].single.ticker, 'SURE');
      expect(result['holdings'].single.amount, r'$40.00');
    });

    test('fetches latest holdings page before returning top holdings',
        () async {
      var requestCount = 0;
      final service = AccountDetailService(
        client: MockClient((request) async {
          requestCount += 1;
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/holdings');
          expect(request.url.queryParameters['account_id'], 'acct_1');
          expect(request.url.queryParameters['per_page'], '100');

          if (requestCount == 1) {
            expect(request.url.queryParameters['page'], '1');
            return http.Response(
              '{"holdings":[{"id":"old_holding","date":"2025-01-01",'
              '"qty":"1.0","price":"\$5.00","amount":"\$5.00",'
              '"currency":"USD","security":{"ticker":"OLD",'
              '"name":"Old Holding"}}],'
              '"pagination":{"page":1,"per_page":100,"total_count":4,'
              '"total_pages":2}}',
              200,
            );
          }

          expect(request.url.queryParameters['page'], '2');
          return http.Response(
            '{"holdings":[{"id":"stale_same_page","date":"2026-05-31",'
            '"qty":"1.0","price":"\$5.00","amount":"\$5.00",'
            '"currency":"USD","security":{"ticker":"STALE",'
            '"name":"Stale Holding"}},'
            '{"id":"small_current","date":"2026-06-01",'
            '"qty":"1.0","price":"\$10.00","amount":"\$10.00",'
            '"currency":"USD","security":{"ticker":"SMALL",'
            '"name":"Small Holding"}},'
            '{"id":"large_current","date":"2026-06-01",'
            '"qty":"1.0","price":"\$125.00","amount":"\$125.00",'
            '"currency":"USD","security":{"ticker":"LARGE",'
            '"name":"Large Holding"}}],'
            '"pagination":{"page":2,"per_page":100,"total_count":4,'
            '"total_pages":2}}',
            200,
          );
        }),
      );

      final result = await service.getHoldings(
        accessToken: 'token',
        accountId: 'acct_1',
        perPage: 1,
      );

      expect(result['success'], true);
      expect(requestCount, 2);
      expect(result['holdings'], hasLength(1));
      expect(result['holdings'].single.ticker, 'LARGE');
    });

    test(
        'latest positions across a page boundary come from a date query, '
        'deduplicated, so a refresh cannot repeat or skip one', () async {
      String row(String id, String date, String ticker, String amount) =>
          '{"id":"$id","date":"$date","qty":"1.0","price":"$amount",'
          '"amount":"$amount","currency":"USD","account":{"id":"acct_1"},'
          '"security":{"id":"sec_$ticker","ticker":"$ticker","name":"$ticker"}}';
      String page(List<String> rows, int page, int pages) =>
          '{"holdings":[${rows.join(',')}],"pagination":{"page":$page,'
          '"per_page":100,"total_count":${pages * 100},"total_pages":$pages}}';

      final requests = <Uri>[];
      final service = AccountDetailService(
        client: MockClient((request) async {
          requests.add(request.url);
          final q = request.url.queryParameters;
          if (q['date'] == '2026-06-01') {
            // The date query: every current position, one of them twice
            // (as an unstable server order can return it).
            return http.Response(
              page([
                row('a', '2026-06-01', 'AAA', r'$30.00'),
                row('b', '2026-06-01', 'BBB', r'$20.00'),
                row('b', '2026-06-01', 'BBB', r'$20.00'),
                row('c', '2026-06-01', 'CCC', r'$10.00'),
              ], 1, 1),
              200,
            );
          }
          // History: the last page is entirely the latest date, so the
          // current positions continue onto page 1, where the server's
          // unstable order repeats BBB and leaves CCC out.
          if (q['page'] == '1') {
            return http.Response(
              page([
                row('old', '2026-05-31', 'OLD', r'$5.00'),
                row('b', '2026-06-01', 'BBB', r'$20.00'),
              ], 1, 2),
              200,
            );
          }
          return http.Response(
            page([
              row('a', '2026-06-01', 'AAA', r'$30.00'),
              row('b', '2026-06-01', 'BBB', r'$20.00'),
            ], 2, 2),
            200,
          );
        }),
      );

      final result = await service.getCurrentHoldings(
        accessToken: 'token',
        accountId: 'acct_1',
      );

      expect(result['success'], true);
      final tickers = [
        for (final h in result['holdings'] as List) (h as dynamic).ticker,
      ];
      expect(tickers, ['AAA', 'BBB', 'CCC']);
      expect(requests.where((u) => u.queryParameters['date'] == '2026-06-01'),
          hasLength(1));
    });

    test(
        'with stableOrder, walks pages back without a date query and '
        'dedupes by id', () async {
      String row(String id, String date, String ticker, String amount) =>
          '{"id":"$id","date":"$date","qty":"1.0","price":"$amount",'
          '"amount":"$amount","currency":"USD","account":{"id":"acct_1"},'
          '"security":{"id":"sec_$ticker","ticker":"$ticker","name":"$ticker"}}';
      String page(List<String> rows, int page, int pages) =>
          '{"holdings":[${rows.join(',')}],"pagination":{"page":$page,'
          '"per_page":100,"total_count":${pages * 100},"total_pages":$pages}}';

      final requests = <Uri>[];
      final service = AccountDetailService(
        client: MockClient((request) async {
          requests.add(request.url);
          // Ordered by (date, id): the latest date fills pages 3 and 2 and
          // begins on page 1. A row repeated across a boundary is dropped.
          switch (request.url.queryParameters['page']) {
            case '1':
              return http.Response(
                page([
                  row('old', '2026-05-31', 'OLD', r'$5.00'),
                  row('a', '2026-06-01', 'AAA', r'$30.00'),
                ], 1, 3),
                200,
              );
            case '2':
              return http.Response(
                page([
                  row('a', '2026-06-01', 'AAA', r'$30.00'),
                  row('b', '2026-06-01', 'BBB', r'$20.00'),
                ], 2, 3),
                200,
              );
            default:
              return http.Response(
                page([row('c', '2026-06-01', 'CCC', r'$10.00')], 3, 3),
                200,
              );
          }
        }),
      );

      final result = await service.getCurrentHoldings(
        accessToken: 'token',
        accountId: 'acct_1',
        stableOrder: true,
      );

      expect(result['success'], true);
      final tickers = [
        for (final h in result['holdings'] as List) (h as dynamic).ticker,
      ];
      expect(tickers, ['AAA', 'BBB', 'CCC']);
      expect(requests.any((u) => u.queryParameters.containsKey('date')),
          isFalse);
      // Page 1 is reused from the first request, not fetched again.
      expect([for (final u in requests) u.queryParameters['page']],
          ['1', '3', '2']);
    });

    test('with stableOrder, a failed earlier page fails the load', () async {
      final service = AccountDetailService(
        client: MockClient((request) async {
          final page = request.url.queryParameters['page'];
          if (page == '2') return http.Response('{}', 500);
          final date = page == '1' ? '2026-05-31' : '2026-06-01';
          return http.Response(
            '{"holdings":[{"id":"h$page","date":"$date","qty":"1.0",'
            '"price":"\$1.00","amount":"\$1.00","currency":"USD",'
            '"security":{"ticker":"T$page","name":"T"}}],'
            '"pagination":{"page":$page,"per_page":100,"total_count":3,'
            '"total_pages":3}}',
            200,
          );
        }),
      );

      final result = await service.getCurrentHoldings(
        accessToken: 'token',
        accountId: 'acct_1',
        stableOrder: true,
      );

      expect(result['success'], false);
    });

    test('parses non-string account balance and holding scalar values',
        () async {
      var requestCount = 0;
      final service = AccountDetailService(
        client: MockClient((request) async {
          requestCount += 1;

          if (request.url.path == '/api/v1/accounts/acct_1') {
            return http.Response(
              '{"id":"acct_1","name":123,"balance":1200.5,'
              '"cash_balance":200,"currency":840,'
              '"classification":true,"account_type":"investment",'
              '"subtype":42,"status":1,"institution_name":987,'
              '"institution_domain":654}',
              200,
            );
          }

          if (request.url.path == '/api/v1/balances') {
            return http.Response(
              '{"balances":[{"id":"bal_1","date":"2026-06-01",'
              '"currency":840,"balance":1200.5,'
              '"cash_balance":200}]}',
              200,
            );
          }

          if (request.url.path == '/api/v1/holdings') {
            return http.Response(
              '{"holdings":[{"id":"holding_1","date":"2026-06-01",'
              '"qty":4,"price":10,"amount":40,"currency":840,'
              '"security":{"ticker":123,"name":456}}],'
              '"pagination":{"page":1,"per_page":100,"total_count":1,'
              '"total_pages":1}}',
              200,
            );
          }

          return http.Response('{}', 404);
        }),
      );

      final accountResult = await service.getAccountDetail(
        accessToken: 'token',
        accountId: 'acct_1',
      );
      final balancesResult = await service.getBalances(
        accessToken: 'token',
        accountId: 'acct_1',
      );
      final holdingsResult = await service.getHoldings(
        accessToken: 'token',
        accountId: 'acct_1',
      );

      expect(requestCount, 3);
      expect(accountResult['success'], true);
      expect(accountResult['account'].cashBalance, '200');
      expect(accountResult['account'].subtype, '42');
      expect(accountResult['account'].institutionDomain, '654');
      expect(balancesResult['success'], true);
      expect(balancesResult['balances'].single.currency, '840');
      expect(balancesResult['balances'].single.balance, '1200.5');
      expect(balancesResult['balances'].single.cashBalance, '200');
      expect(holdingsResult['success'], true);
      expect(holdingsResult['holdings'].single.price, '10');
      expect(holdingsResult['holdings'].single.amount, '40');
      expect(holdingsResult['holdings'].single.currency, '840');
      expect(holdingsResult['holdings'].single.ticker, '123');
      expect(holdingsResult['holdings'].single.securityName, '456');
    });

    test('returns generic error for malformed holding dates', () async {
      final service = AccountDetailService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/holdings');
          expect(request.url.queryParameters['page'], '1');
          return http.Response(
            '{"holdings":[{"id":"holding_1","date":"not-a-date",'
            '"qty":"4.0","price":"\$10.00","amount":"\$40.00",'
            '"currency":"USD"}],'
            '"pagination":{"page":1,"per_page":100,"total_count":1,'
            '"total_pages":1}}',
            200,
          );
        }),
      );

      final result = await service.getHoldings(
        accessToken: 'token',
        accountId: 'acct_1',
      );

      expect(result['success'], false);
      expect(
          result['error'], 'Unable to load holdings. Please try again later.');
    });
  });
}
