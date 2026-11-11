import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/account.dart';
import 'package:sure_mobile/services/account_detail_service.dart';
import 'package:sure_mobile/services/net_worth_history_service.dart';
import 'package:sure_mobile/utils/net_worth_history.dart';

Account _account(
  String id, {
  String currency = 'USD',
  String classification = 'asset',
  int cents = 0,
}) =>
    Account(
      id: id,
      name: id,
      balance: '$cents',
      balanceCents: cents,
      currency: currency,
      classification: classification,
      accountType: 'depository',
    );

String _balances(List<List<Object>> rows) => jsonEncode({
      'balances': [
        for (final r in rows)
          {
            'id': '${r[0]}',
            'date': r[0],
            'currency': r.length > 2 ? r[2] : 'USD',
            'balance': '${r[1]}',
            'balance_cents': r[1],
          },
      ],
      'pagination': {'page': 1, 'per_page': 100, 'total_count': 1, 'total_pages': 1},
    });

void main() {
  final start = DateTime(2026, 10, 1);
  final end = DateTime(2026, 10, 3);

  test('fetches main-currency accounts from start_date and sums them',
      () async {
    final requested = <Uri>[];
    final service = NetWorthHistoryService(
      accountDetailService: AccountDetailService(
        client: MockClient((request) async {
          requested.add(request.url);
          expect(request.url.path, '/api/v1/balances');
          expect(request.headers['Authorization'], 'Bearer token');
          final id = request.url.queryParameters['account_id'];
          return http.Response(
            id == 'cash'
                ? _balances([
                    ['2026-10-02', 2000],
                    ['2026-10-01', 1000],
                  ])
                : _balances([
                    ['2026-10-01', 300],
                  ]),
            200,
          );
        }),
      ),
    );

    final result = await service.load(
      accessToken: 'token',
      accounts: [
        _account('cash'),
        _account('card', classification: 'liability'),
        _account('uk', currency: 'GBP', cents: 50000),
      ],
      mainCurrency: 'USD',
      start: start,
      end: end,
    );

    expect(result['success'], true);
    final history = result['history'] as NetWorthHistory;
    expect(history.points.map((p) => p.cents), [700, 1700, 1700]);
    expect(history.otherCurrencies.single.currency, 'GBP');
    expect(history.otherCurrencies.single.cents, 50000);
    // The GBP account is not fetched.
    expect(requested.map((u) => u.queryParameters['account_id']).toSet(),
        {'cash', 'card'});
    expect(requested.first.queryParameters['start_date'], '2026-10-01');
  });

  test('never runs more than maxConcurrent requests at once', () async {
    var active = 0;
    var peak = 0;
    final service = NetWorthHistoryService(
      accountDetailService: AccountDetailService(
        client: MockClient((request) async {
          active++;
          if (active > peak) peak = active;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          active--;
          return http.Response(_balances([
            ['2026-10-01', 1],
          ]), 200);
        }),
      ),
    );

    final result = await service.load(
      accessToken: 'token',
      accounts: [for (var i = 0; i < 10; i++) _account('a$i')],
      mainCurrency: 'USD',
      start: start,
      end: end,
    );

    expect(result['success'], true);
    expect((result['history'] as NetWorthHistory).currentCents, 10);
    expect(peak, NetWorthHistoryService.maxConcurrent);
  });

  test('a 401 on any account reports unauthorized', () async {
    final service = NetWorthHistoryService(
      accountDetailService: AccountDetailService(
        client: MockClient((request) async {
          final id = request.url.queryParameters['account_id'];
          if (id == 'b') return http.Response('{}', 401);
          if (id == 'c') return http.Response('{}', 500);
          return http.Response(_balances([
            ['2026-10-01', 1],
          ]), 200);
        }),
      ),
    );

    final result = await service.load(
      accessToken: 'token',
      accounts: [_account('a'), _account('b'), _account('c')],
      mainCurrency: 'USD',
      start: start,
      end: end,
    );

    expect(result, {'success': false, 'error': 'unauthorized'});
  });

  test('a server error fails the whole load', () async {
    final service = NetWorthHistoryService(
      accountDetailService: AccountDetailService(
        client: MockClient((_) async => http.Response('{}', 500)),
      ),
    );

    final result = await service.load(
      accessToken: 'token',
      accounts: [_account('a')],
      mainCurrency: 'USD',
      start: start,
      end: end,
    );

    expect(result['success'], false);
    expect(result['error'], isNot('unauthorized'));
  });

  test('no accounts makes no requests and an empty history', () async {
    final service = NetWorthHistoryService(
      accountDetailService: AccountDetailService(
        client: MockClient((_) async => fail('no request expected')),
      ),
    );

    final result = await service.load(
      accessToken: 'token',
      accounts: const [],
      mainCurrency: 'USD',
      start: start,
      end: end,
    );

    expect(result['success'], true);
    expect((result['history'] as NetWorthHistory).points, isEmpty);
  });
}
