import 'dart:convert';

import 'api_config.dart';
import 'auth_service.dart';
import 'database_helper.dart';
import 'log_service.dart';

/// A cached response and when it was saved.
class CachedEntry {
  const CachedEntry({required this.data, required this.savedAt});

  /// The decoded JSON value that was written.
  final Object? data;
  final DateTime savedAt;
}

/// Last-good API responses, so screens can draw at once on launch and stay
/// readable offline.
///
/// Every entry belongs to a scope built from the configured server URL and
/// the signed-in user ([scopeFor]), so one account's data is never read for
/// another. Entries older than [maxAge] are treated as missing. The whole
/// cache is cleared on sign-out and when the server URL changes.
///
/// Stored in the app's sqlite database (`response_cache`, see
/// [DatabaseHelper]); on web that falls back to memory. Failures are logged
/// and treated as a cache miss: the cache never breaks a load.
class OfflineCacheStore {
  OfflineCacheStore({
    DatabaseHelper? db,
    Future<String?> Function()? scopeResolver,
    DateTime Function()? clock,
    this.maxAge = defaultMaxAge,
  })  : _db = db ?? DatabaseHelper.instance,
        _scopeResolver = scopeResolver ?? _storedAuthScope,
        _clock = clock ?? DateTime.now;

  /// Shared store used by the providers. Tests may replace it.
  static OfflineCacheStore instance = OfflineCacheStore();

  static const Duration defaultMaxAge = Duration(days: 30);

  static const String accountsKey = 'accounts';
  static const String balanceSheetKey = 'balance_sheet';
  static const String budgetsCurrentPeriodKey = 'budgets:current_period';
  static String budgetsMonthKey(String month) => 'budgets:$month';

  final DatabaseHelper _db;
  final Future<String?> Function() _scopeResolver;
  final DateTime Function() _clock;
  final Duration maxAge;
  final LogService _log = LogService.instance;

  /// Scope for [baseUrl] (trailing slashes and case ignored) and [userKey].
  static String scopeFor(String baseUrl, String userKey) {
    final server = baseUrl.trim().replaceAll(RegExp(r'/+$'), '').toLowerCase();
    return '$server|$userKey';
  }

  /// The scope of the signed-in user on the configured server, or null when
  /// nobody is signed in (nothing is read or written then). A stalled
  /// secure-storage read gives up after [scopeTimeout] rather than hold up
  /// the screen.
  Future<String?> currentScope() async {
    try {
      return await _scopeResolver().timeout(scopeTimeout);
    } catch (e) {
      _log.warning('OfflineCache', 'Could not resolve scope: ${e.runtimeType}');
      return null;
    }
  }

  static const Duration scopeTimeout = Duration(seconds: 2);

  Future<CachedEntry?> read(String scope, String key) async {
    try {
      final row = await _db.getCacheEntry(scope, key);
      if (row == null) return null;
      final savedAt = DateTime.tryParse(row['saved_at'] as String? ?? '');
      if (savedAt == null || _clock().difference(savedAt) > maxAge) {
        await _db.deleteCacheEntry(scope, key);
        return null;
      }
      return CachedEntry(
        data: jsonDecode(row['payload'] as String),
        savedAt: savedAt.toLocal(),
      );
    } catch (e) {
      _log.warning('OfflineCache', 'Read of $key failed: ${e.runtimeType}');
      return null;
    }
  }

  /// Saves [data] (any JSON-encodable value) and returns the time it saved.
  Future<DateTime> write(String scope, String key, Object? data) async {
    final now = _clock();
    try {
      await _db.putCacheEntry(scope, key, jsonEncode(data), now);
    } catch (e) {
      _log.warning('OfflineCache', 'Write of $key failed: ${e.runtimeType}');
    }
    return now;
  }

  /// Removes every cached response for every scope, plus the older cached
  /// rows that are not scoped by user: the `accounts` table and synced
  /// transaction copies. Pending and failed offline transactions are kept so
  /// the existing offline queue is unchanged. Used on sign-out and when the
  /// server URL changes.
  Future<void> clearAll() async {
    try {
      await _db.clearCacheEntries();
      await _db.clearAccounts();
      await _db.clearSyncedTransactions();
    } catch (e) {
      _log.warning('OfflineCache', 'Clear failed: ${e.runtimeType}');
    }
  }

  static Future<String?> _storedAuthScope() async {
    final auth = AuthService();
    String? userKey;
    if (await auth.getStoredAuthMode() == 'api_key') {
      // API-key sign-in stores no user, so key on a fingerprint of the key
      // (never the key itself).
      final apiKey = await auth.getStoredApiKey();
      if (apiKey != null && apiKey.isNotEmpty) userKey = 'key:${fnv1a32(apiKey)}';
    } else {
      final user = await auth.getStoredUser();
      if (user != null && user.id.isNotEmpty) userKey = 'user:${user.id}';
    }
    if (userKey == null) return null;
    return scopeFor(ApiConfig.baseUrl, userKey);
  }

  /// 32-bit FNV-1a as hex. Only separates cache scopes; not a security hash.
  /// Written without 64-bit overflow so it gives the same result on web.
  static String fnv1a32(String input) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(input)) {
      hash ^= byte;
      // hash * 16777619 mod 2^32, with 16777619 = 2^24 + 403.
      hash = ((hash & 0xff) * 0x1000000 + hash * 403) % 0x100000000;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
