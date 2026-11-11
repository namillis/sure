import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/services/database_helper.dart';
import 'package:sure_mobile/services/offline_cache_store.dart';

import '../support/test_database.dart';

void main() {
  late DateTime now;
  late String? scope;

  OfflineCacheStore store({Duration maxAge = const Duration(days: 30)}) =>
      OfflineCacheStore(
        scopeResolver: () async => scope,
        clock: () => now,
        maxAge: maxAge,
      );

  setUp(() async {
    await openTestDatabase();
    now = DateTime.utc(2026, 11, 11, 12);
    scope = OfflineCacheStore.scopeFor('https://sure.example.test', 'user:1');
  });

  tearDown(closeTestDatabase);

  test('writes and reads back JSON with its save time', () async {
    final cache = store();
    final s = (await cache.currentScope())!;
    final savedAt = await cache.write(s, 'accounts', [
      {'id': 'a1', 'name': 'Checking'},
    ]);

    final entry = await cache.read(s, 'accounts');
    expect(entry, isNotNull);
    expect(entry!.data, [
      {'id': 'a1', 'name': 'Checking'},
    ]);
    expect(entry.savedAt.isAtSameMomentAs(savedAt), isTrue);
  });

  test('a later write replaces the earlier one', () async {
    final cache = store();
    final s = (await cache.currentScope())!;
    await cache.write(s, 'k', {'v': 1});
    now = now.add(const Duration(minutes: 5));
    await cache.write(s, 'k', {'v': 2});

    final entry = await cache.read(s, 'k');
    expect(entry!.data, {'v': 2});
    expect(entry.savedAt.isAtSameMomentAs(now), isTrue);
  });

  test('missing key reads as null', () async {
    final cache = store();
    expect(await cache.read((await cache.currentScope())!, 'nope'), isNull);
  });

  test('entries older than maxAge are dropped', () async {
    final cache = store(maxAge: const Duration(days: 1));
    final s = (await cache.currentScope())!;
    await cache.write(s, 'k', {'v': 1});

    now = now.add(const Duration(hours: 23));
    expect(await cache.read(s, 'k'), isNotNull);

    now = now.add(const Duration(hours: 2));
    expect(await cache.read(s, 'k'), isNull);
    // Removed, not just hidden.
    expect(await DatabaseHelper.instance.getCacheEntry(s, 'k'), isNull);
  });

  test('isolates data by server and by user', () async {
    final cache = store();
    final a = OfflineCacheStore.scopeFor('https://one.example.test', 'user:1');
    final b = OfflineCacheStore.scopeFor('https://two.example.test', 'user:1');
    final c = OfflineCacheStore.scopeFor('https://one.example.test', 'user:2');
    await cache.write(a, 'accounts', ['a']);
    await cache.write(b, 'accounts', ['b']);

    expect((await cache.read(a, 'accounts'))!.data, ['a']);
    expect((await cache.read(b, 'accounts'))!.data, ['b']);
    expect(await cache.read(c, 'accounts'), isNull);
  });

  test('scope ignores trailing slashes and case in the server URL', () {
    expect(
      OfflineCacheStore.scopeFor('https://Sure.Example.test//', 'user:1'),
      OfflineCacheStore.scopeFor('https://sure.example.test', 'user:1'),
    );
  });

  test('no signed-in user gives no scope', () async {
    scope = null;
    expect(await store().currentScope(), isNull);
  });

  test('a scope lookup that never answers gives no scope', () async {
    final cache = OfflineCacheStore(
      scopeResolver: () => Completer<String?>().future,
    );
    expect(await cache.currentScope(), isNull);
  });

  test('clearAll (sign-out, server change) removes every scope', () async {
    final cache = store();
    final a = OfflineCacheStore.scopeFor('https://one.example.test', 'user:1');
    final b = OfflineCacheStore.scopeFor('https://two.example.test', 'user:2');
    await cache.write(a, 'accounts', ['a']);
    await cache.write(b, 'balance_sheet', {'x': 1});

    await cache.clearAll();

    expect(await cache.read(a, 'accounts'), isNull);
    expect(await cache.read(b, 'balance_sheet'), isNull);
  });

  test('clearAll keeps pending offline transactions, drops synced copies',
      () async {
    final db = DatabaseHelper.instance;
    Map<String, dynamic> txn(String id, String status) => {
          'local_id': id,
          'account_id': 'a1',
          'name': 'Coffee',
          'date': '2026-11-10',
          'amount': '3.00',
          'currency': 'USD',
          'nature': 'expense',
          'sync_status': status,
          'created_at': '2026-11-10T00:00:00Z',
          'updated_at': '2026-11-10T00:00:00Z',
        };
    await db.insertTransaction(txn('pending', 'pending'));
    await db.insertTransaction(txn('synced', 'synced'));

    await store().clearAll();

    final left = await db.getTransactions();
    expect(left.map((t) => t['local_id']), ['pending']);
  });

  test('fnv1a32 is stable and separates inputs', () {
    expect(OfflineCacheStore.fnv1a32(''), '811c9dc5');
    expect(OfflineCacheStore.fnv1a32('a'), 'e40c292c');
    expect(
      OfflineCacheStore.fnv1a32('key-one'),
      isNot(OfflineCacheStore.fnv1a32('key-two')),
    );
  });
}
