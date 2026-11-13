import 'dart:convert';

import 'package:sure_mobile/services/offline_cache_store.dart';

/// The on-device cache in memory: the sqlite one does real I/O, which never
/// completes inside a widget test's fake time.
class MemoryCache extends OfflineCacheStore {
  MemoryCache() : super(scopeResolver: () async => 's');

  final _entries = <String, CachedEntry>{};

  /// When the next write is stamped.
  DateTime savedAt = DateTime(2026, 11, 11, 11);

  @override
  Future<CachedEntry?> read(String scope, String key) async =>
      _entries['$scope|$key'];

  @override
  Future<DateTime> write(String scope, String key, Object? data) async {
    _entries['$scope|$key'] =
        CachedEntry(data: jsonDecode(jsonEncode(data)), savedAt: savedAt);
    return savedAt;
  }
}
