import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sure_mobile/services/database_helper.dart';

/// Points [DatabaseHelper.instance] at a fresh sqlite file in a temp
/// directory (desktop ffi), migrated to the current schema. Call
/// [closeTestDatabase] in tearDown.
Future<Database> openTestDatabase() async {
  if (!_ffiReady) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _ffiReady = true;
  }
  final dir = await Directory.systemTemp.createTemp('sure_db_test');
  final db = await DatabaseHelper.openAt(p.join(dir.path, 'test.db'));
  DatabaseHelper.setDatabaseForTesting(db);
  return db;
}

Future<void> closeTestDatabase() async {
  await DatabaseHelper.instance.close();
}

bool _ffiReady = false;
