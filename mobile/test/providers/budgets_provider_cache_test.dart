import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/providers/budgets_provider.dart';
import 'package:sure_mobile/services/budgets_service.dart';
import 'package:sure_mobile/services/offline_cache_store.dart';

import '../support/budget_fixtures.dart';
import '../support/test_database.dart';

void main() {
  late String scope;
  late OfflineCacheStore cache;

  BudgetsProvider build({
    required bool Function() isOffline,
    http.Client? client,
    List<http.Request>? log,
    List<Map<String, dynamic>>? budgets,
    DateTime Function()? now,
  }) =>
      BudgetsProvider(
        service: BudgetsService(
          client: client ?? budgetsMockClient(log: log, budgets: budgets),
        ),
        clock: now ?? () => DateTime(2026, 10, 19),
        isOffline: isOffline,
        cache: cache,
      );

  /// Month writes are fire-and-forget; wait until [key] is on disk.
  Future<void> waitForCached(String key) async {
    for (var i = 0; i < 100; i++) {
      if (await cache.read(scope, key) != null) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('$key was never cached');
  }

  setUp(() async {
    await openTestDatabase();
    scope = OfflineCacheStore.scopeFor('https://sure.example.test', 'user:1');
    cache = OfflineCacheStore(scopeResolver: () async => scope);
  });

  tearDown(closeTestDatabase);

  test('a month loaded online is shown offline after a relaunch', () async {
    final first = build(isOffline: () => false);
    await first.loadMonth(accessToken: 't');
    final categoryCount = first.categories.length;
    expect(categoryCount, greaterThan(0));
    await waitForCached(OfflineCacheStore.budgetsMonthKey('2026-10'));
    first.dispose();

    final log = <http.Request>[];
    final relaunched = build(isOffline: () => true, log: log);
    await relaunched.loadMonth(accessToken: 't');

    expect(log, isEmpty);
    expect(relaunched.error, isNull);
    expect(relaunched.showingCachedWhileOffline, isTrue);
    expect(relaunched.budget?.id, 'budget_oct');
    expect(relaunched.budget?.actualSpendingCents, isNotNull);
    expect(relaunched.categories.length, categoryCount);
    expect(
      relaunched.categories.map((c) => c.actualSpendingCents),
      first.categories.map((c) => c.actualSpendingCents),
    );
  });

  test('online, the cached month shows while the refresh runs', () async {
    final first = build(isOffline: () => false);
    await first.loadMonth(accessToken: 't');
    await waitForCached(OfflineCacheStore.budgetsMonthKey('2026-10'));
    first.dispose();

    final gate = Completer<void>();
    var held = 0;
    final handler = budgetsMockHandler();
    final provider = build(
      isOffline: () => false,
      client: MockClient((request) async {
        // Let the current-period lookup through, hold the month fetch.
        if (request.url.queryParameters.containsKey('start_date') &&
            held++ == 0) {
          return handler(request);
        }
        await gate.future;
        return handler(request);
      }),
    );

    final done = provider.loadMonth(accessToken: 't');
    while (!provider.isLoading || !provider.hasLoadedMonth) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(provider.budget?.id, 'budget_oct');

    gate.complete();
    await done;
    expect(provider.isLoading, isFalse);
    expect(provider.error, isNull);
    expect(provider.budget?.id, 'budget_oct');
    // Let the refreshed month's write finish before the database closes.
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  test('offline opens on the custom period saved by an online load',
      () async {
    final budgets = [
      budgetJson(
        id: 'budget_sep',
        startDate: '2026-09-15',
        endDate: '2026-10-14',
        name: 'Sep 15 - Oct 14, 2026',
      ),
    ];
    DateTime now() => DateTime(2026, 10, 10);
    final first = build(isOffline: () => false, budgets: budgets, now: now);
    await first.loadMonth(accessToken: 't');
    expect(first.month, DateTime(2026, 9));
    await waitForCached(OfflineCacheStore.budgetsMonthKey('2026-09'));
    first.dispose();

    final relaunched = build(isOffline: () => true, now: now);
    await relaunched.loadMonth(accessToken: 't');

    expect(relaunched.month, DateTime(2026, 9));
    expect(relaunched.budget?.id, 'budget_sep');
    expect(relaunched.showingCachedWhileOffline, isTrue);
  });

  test("another user's cached month is not shown", () async {
    final first = build(isOffline: () => false);
    await first.loadMonth(accessToken: 't');
    await waitForCached(OfflineCacheStore.budgetsMonthKey('2026-10'));
    first.dispose();

    scope = OfflineCacheStore.scopeFor('https://sure.example.test', 'user:2');
    final other = build(isOffline: () => true);
    await other.loadMonth(accessToken: 't');

    expect(other.error, BudgetsLoadError.offline);
    expect(other.hasLoadedMonth, isFalse);
  });
}
