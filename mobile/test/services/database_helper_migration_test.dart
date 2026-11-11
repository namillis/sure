import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sure_mobile/services/database_helper.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('upgrading a version 3 database adds response_cache and keeps data',
      () async {
    final dir = await Directory.systemTemp.createTemp('sure_migration');
    final path = p.join(dir.path, 'v3.db');

    // The schema as version 3 created it.
    final old = await openDatabase(
      path,
      version: 3,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE transactions (
            local_id TEXT PRIMARY KEY, server_id TEXT,
            account_id TEXT NOT NULL, name TEXT NOT NULL, date TEXT NOT NULL,
            amount TEXT NOT NULL, currency TEXT NOT NULL, nature TEXT NOT NULL,
            notes TEXT, category_id TEXT, category_name TEXT,
            merchant_id TEXT, merchant_name TEXT,
            tag_ids TEXT DEFAULT '[]', tag_names TEXT DEFAULT '[]',
            sync_status TEXT NOT NULL,
            created_at TEXT NOT NULL, updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE accounts (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, balance TEXT NOT NULL,
            currency TEXT NOT NULL, classification TEXT,
            account_type TEXT NOT NULL, synced_at TEXT NOT NULL
          )
        ''');
      },
    );
    await old.insert('transactions', {
      'local_id': 'l1',
      'account_id': 'a1',
      'name': 'Pending coffee',
      'date': '2026-11-10',
      'amount': '3.00',
      'currency': 'USD',
      'nature': 'expense',
      'sync_status': 'pending',
      'created_at': '2026-11-10T00:00:00Z',
      'updated_at': '2026-11-10T00:00:00Z',
    });
    await old.close();

    final db = await DatabaseHelper.openAt(path);
    expect(await db.getVersion(), DatabaseHelper.schemaVersion);
    expect(DatabaseHelper.schemaVersion, 4);

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='response_cache'",
    );
    expect(tables, hasLength(1));

    await db.insert('response_cache', {
      'scope': 's',
      'cache_key': 'k',
      'payload': '{}',
      'saved_at': '2026-11-11T00:00:00Z',
    });
    expect(await db.query('response_cache'), hasLength(1));

    final txns = await db.query('transactions');
    expect(txns.single['name'], 'Pending coffee');
    expect(txns.single['sync_status'], 'pending');
    await db.close();
  });

  test('a fresh database has response_cache', () async {
    final dir = await Directory.systemTemp.createTemp('sure_fresh');
    final db = await DatabaseHelper.openAt(p.join(dir.path, 'fresh.db'));
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    expect(
      tables.map((t) => t['name']),
      containsAll(['accounts', 'response_cache', 'transactions']),
    );
    await db.close();
  });
}
