import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/providers/accounts_provider.dart';
import 'package:sure_mobile/services/accounts_service.dart';
import 'package:sure_mobile/services/balance_sheet_service.dart';
import 'package:sure_mobile/services/offline_cache_store.dart';

import '../support/test_database.dart';

class _FakeBalanceSheet extends BalanceSheetService {
  _FakeBalanceSheet(this.netWorth);
  String? netWorth;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> getBalanceSheet({
    required String accessToken,
  }) async {
    calls++;
    if (netWorth == null) return {'success': false, 'error': 'failed'};
    return {
      'success': true,
      'currency': 'USD',
      'net_worth': {'formatted': netWorth},
      'assets': {'formatted': netWorth},
      'liabilities': {'formatted': r'$0.00'},
    };
  }
}

Map<String, dynamic> _account(String id, String name, String balance) => {
      'id': id,
      'name': name,
      'balance': balance,
      'currency': 'USD',
      'classification': 'asset',
      'account_type': 'depository',
    };

void main() {
  late String scope;
  late OfflineCacheStore cache;
  late List<Map<String, dynamic>> serverAccounts;
  late int statusCode;
  late int requests;
  Completer<void>? gate;
  var online = true;
  late _FakeBalanceSheet sheet;

  AccountsProvider build() => AccountsProvider(
        accountsService: AccountsService(
          client: MockClient((request) async {
            requests++;
            if (gate != null) await gate!.future;
            if (statusCode != 200) {
              return http.Response(jsonEncode({'error': 'x'}), statusCode);
            }
            return http.Response(
              jsonEncode({
                'accounts': serverAccounts,
                'pagination': {'page': 1, 'total_pages': 1},
              }),
              200,
            );
          }),
        ),
        balanceSheetService: sheet,
        cache: cache,
        isOnline: () => online,
      );

  setUp(() async {
    await openTestDatabase();
    scope = OfflineCacheStore.scopeFor('https://sure.example.test', 'user:1');
    cache = OfflineCacheStore(scopeResolver: () async => scope);
    serverAccounts = [_account('a1', 'Checking', r'$200.00')];
    statusCode = 200;
    requests = 0;
    gate = null;
    online = true;
    sheet = _FakeBalanceSheet(r'$200.00');
  });

  tearDown(closeTestDatabase);

  Future<void> seedCache() async {
    await cache.write(scope, OfflineCacheStore.accountsKey, [
      _account('a1', 'Checking', r'$100.00'),
    ]);
    await cache.write(scope, OfflineCacheStore.balanceSheetKey, {
      'currency': 'USD',
      'net_worth': {'formatted': r'$100.00'},
      'assets': {'formatted': r'$100.00'},
      'liabilities': {'formatted': r'$0.00'},
    });
  }

  test('shows cached data at once, then replaces it with the server copy',
      () async {
    await seedCache();
    gate = Completer<void>();
    final provider = build();

    final done = provider.fetchAccounts(accessToken: 't');
    // Let the cache read finish while the network request is held.
    while (requests == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(provider.accounts.single.balance, r'$100.00');
    expect(provider.netWorthFormatted, r'$100.00');
    expect(provider.isShowingCachedData, isTrue);
    expect(provider.isInitializing, isFalse);
    final cachedAt = provider.lastUpdatedAt;
    expect(cachedAt, isNotNull);

    gate!.complete();
    await done;

    expect(provider.accounts.single.balance, r'$200.00');
    expect(provider.netWorthFormatted, r'$200.00');
    expect(provider.isShowingCachedData, isFalse);
    expect(provider.errorMessage, isNull);

    // The fresh copy was saved for the next launch.
    final saved = await cache.read(scope, OfflineCacheStore.accountsKey);
    expect(((saved!.data as List).single as Map)['balance'], r'$200.00');
    final savedSheet =
        await cache.read(scope, OfflineCacheStore.balanceSheetKey);
    expect(
      ((savedSheet!.data as Map)['net_worth'] as Map)['formatted'],
      r'$200.00',
    );
  });

  test('offline keeps the cached copy and makes no request', () async {
    await seedCache();
    online = false;
    final provider = build();

    final ok = await provider.fetchAccounts(accessToken: 't');

    expect(ok, isTrue);
    expect(requests, 0);
    expect(sheet.calls, 0);
    expect(provider.accounts.single.balance, r'$100.00');
    expect(provider.netWorthFormatted, r'$100.00');
    expect(provider.isShowingCachedData, isTrue);
    expect(provider.errorMessage, isNull);
  });

  test('offline with no cache reports an error', () async {
    online = false;
    final provider = build();

    final ok = await provider.fetchAccounts(accessToken: 't');

    expect(ok, isFalse);
    expect(provider.accounts, isEmpty);
    expect(provider.errorMessage, isNotNull);
  });

  test('a failed refresh keeps the cached copy on screen', () async {
    await seedCache();
    statusCode = 500;
    sheet.netWorth = null;
    final provider = build();

    await provider.fetchAccounts(accessToken: 't');

    expect(provider.accounts.single.balance, r'$100.00');
    expect(provider.isShowingCachedData, isTrue);
    expect(provider.isBalanceSheetStale, isTrue);
    expect(provider.errorMessage, isNull);
  });

  test('401 reports unauthorized even with cached data shown', () async {
    await seedCache();
    statusCode = 401;
    final provider = build();

    await provider.fetchAccounts(accessToken: 't');

    expect(provider.errorMessage, 'unauthorized');
  });

  test("never shows another user's cached data", () async {
    await seedCache();
    online = false;
    final provider = build();
    await provider.fetchAccounts(accessToken: 't');
    expect(provider.accounts, isNotEmpty);

    // Same provider, now another user on the same server.
    scope = OfflineCacheStore.scopeFor('https://sure.example.test', 'user:2');
    await provider.fetchAccounts(accessToken: 't');

    expect(provider.accounts, isEmpty);
    expect(provider.netWorthFormatted, isNull);
    expect(provider.lastUpdatedAt, isNull);
  });

  test('cache cleared on sign-out leaves nothing to show', () async {
    await seedCache();
    await cache.clearAll();
    online = false;
    final provider = build();

    await provider.fetchAccounts(accessToken: 't');

    expect(provider.accounts, isEmpty);
    expect(provider.netWorthFormatted, isNull);
  });
}
