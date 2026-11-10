import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/account_trade.dart';
import 'package:sure_mobile/models/trade_security.dart';
import 'package:sure_mobile/services/trades_service.dart';

const _tradeJson = '{"id":"trade_1","date":"2026-11-10","amount":"\$1,505.00",'
    '"currency":"USD","name":"Buy 10.0 shares of AAPL","notes":null,'
    '"qty":"10.0","price":"\$150.00","investment_activity_label":"Buy",'
    '"account":{"id":"acct_1","name":"Brokerage","account_type":"investment"},'
    '"security":{"id":"sec_1","ticker":"AAPL","name":"Apple Inc."},'
    '"category":null,"created_at":"2026-11-10T12:00:00Z",'
    '"updated_at":"2026-11-10T12:00:00Z"}';

void main() {
  group('TradesService', () {
    test('createTrade posts a buy with a ticker and fee', () async {
      final service = TradesService(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/trades');
          expect(request.headers['Authorization'], 'Bearer token');
          expect(jsonDecode(request.body), {
            'trade': {
              'account_id': 'acct_1',
              'type': 'buy',
              'date': '2026-11-10',
              'qty': '10',
              'price': '150',
              'fee': '5',
              'ticker': 'AAPL',
              'currency': 'USD',
            },
          });
          return http.Response(_tradeJson, 201);
        }),
      );

      final result = await service.createTrade(
        accessToken: 'token',
        accountId: 'acct_1',
        type: 'buy',
        date: '2026-11-10',
        qty: '10',
        price: '150',
        fee: '5',
        ticker: 'AAPL',
        currency: 'USD',
      );

      expect(result['success'], true);
      final trade = result['trade'] as AccountTrade;
      expect(trade.id, 'trade_1');
      expect(trade.ticker, 'AAPL');
      expect(trade.activityLabel, 'Buy');
    });

    test('createTrade sends security_id instead of ticker when known',
        () async {
      final service = TradesService(
        client: MockClient((request) async {
          final trade = jsonDecode(request.body)['trade'] as Map;
          expect(trade['security_id'], 'sec_1');
          expect(trade.containsKey('ticker'), false);
          expect(trade.containsKey('fee'), false);
          expect(trade['type'], 'sell');
          return http.Response(_tradeJson, 201);
        }),
      );

      final result = await service.createTrade(
        accessToken: 'token',
        accountId: 'acct_1',
        type: 'sell',
        date: '2026-11-10',
        qty: '2',
        price: '150',
        securityId: 'sec_1',
        ticker: 'AAPL',
      );
      expect(result['success'], true);
    });

    test('createTrade surfaces the server refusal', () async {
      final service = TradesService(
        client: MockClient((_) async => http.Response(
              '{"error":"validation_failed","message":"Account does not support '
              'trades (investment or crypto exchange only)","errors":["Account '
              'must be an investment or crypto exchange account"]}',
              422,
            )),
      );

      final result = await service.createTrade(
        accessToken: 'token',
        accountId: 'acct_1',
        type: 'buy',
        date: '2026-11-10',
        qty: '1',
        price: '1',
        ticker: 'BTC',
      );
      expect(result['success'], false);
      expect(result['error'], contains('crypto exchange'));
    });

    test('updateTrade patches type, date, qty and price', () async {
      final service = TradesService(
        client: MockClient((request) async {
          expect(request.method, 'PATCH');
          expect(request.url.path, '/api/v1/trades/trade_1');
          expect(jsonDecode(request.body), {
            'trade': {
              'type': 'sell',
              'date': '2026-11-09',
              'qty': '3',
              'price': '151.25',
            },
          });
          return http.Response(_tradeJson, 200);
        }),
      );

      final result = await service.updateTrade(
        accessToken: 'token',
        tradeId: 'trade_1',
        type: 'sell',
        date: '2026-11-09',
        qty: '3',
        price: '151.25',
      );
      expect(result['success'], true);
      expect(result['trade'], isA<AccountTrade>());
    });

    test('deleteTrade sends DELETE to the trade path', () async {
      final service = TradesService(
        client: MockClient((request) async {
          expect(request.method, 'DELETE');
          expect(request.url.path, '/api/v1/trades/trade_1');
          return http.Response('{"message":"Trade deleted successfully"}', 200);
        }),
      );

      final result =
          await service.deleteTrade(accessToken: 'token', tradeId: 'trade_1');
      expect(result, {'success': true});
    });

    test('getSecurities lists the family securities', () async {
      final service = TradesService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/securities');
          expect(request.url.queryParameters, {'per_page': '100'});
          return http.Response(
            '{"securities":[{"id":"sec_1","ticker":"AAPL","name":"Apple Inc.",'
            '"exchange_operating_mic":"XNAS"},{"id":"sec_2","ticker":"VTI",'
            '"name":"Vanguard Total Stock Market ETF","exchange_operating_mic":null}],'
            '"pagination":{"page":1,"per_page":100,"total_count":2,"total_pages":1}}',
            200,
          );
        }),
      );

      final result = await service.getSecurities(accessToken: 'token');
      expect(result['success'], true);
      final securities = result['securities'] as List<TradeSecurity>;
      expect(securities.map((s) => s.ticker), ['AAPL', 'VTI']);
      expect(securities.first.exchangeOperatingMic, 'XNAS');
      expect(securities.where((s) => s.matches('vang')).single.id, 'sec_2');
      expect(securities.where((s) => s.matches('aa')).single.id, 'sec_1');
    });

    for (final call in <String, Future<Map<String, dynamic>> Function(TradesService)>{
      'createTrade': (s) => s.createTrade(
            accessToken: 'token',
            accountId: 'acct_1',
            type: 'buy',
            date: '2026-11-10',
            qty: '1',
            price: '1',
            ticker: 'AAPL',
          ),
      'updateTrade': (s) => s.updateTrade(
            accessToken: 'token',
            tradeId: 'trade_1',
            type: 'buy',
            date: '2026-11-10',
            qty: '1',
            price: '1',
          ),
      'deleteTrade': (s) => s.deleteTrade(accessToken: 'token', tradeId: 't'),
      'getSecurities': (s) => s.getSecurities(accessToken: 'token'),
    }.entries) {
      test('${call.key} returns unauthorized on 401', () async {
        final service = TradesService(
          client: MockClient(
              (_) async => http.Response('{"error":"unauthorized"}', 401)),
        );
        final result = await call.value(service);
        expect(result, {'success': false, 'error': 'unauthorized'});
      });
    }
  });
}
