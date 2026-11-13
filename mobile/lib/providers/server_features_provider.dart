import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_config.dart';
import '../services/log_service.dart';
import 'auth_provider.dart';

/// Which Sure+ server extensions the signed-in server offers.
///
/// Gabriel's fork of Sure lists them under `features` in the authenticated
/// `GET /api/v1/version`; stock Sure sends no `features` key, so every check
/// here is false there and screens keep their web fallback. The list is cached
/// per server URL and user, so a launch can use it before the network answers,
/// and refreshed on launch and on every sign-in.
class ServerFeaturesProvider with ChangeNotifier {
  ServerFeaturesProvider({http.Client? client}) : _client = client;

  static const holdingsStableOrder = 'holdings.stable_order';
  static const recurringCategory = 'recurring.category';
  static const budgetsWrite = 'budgets.write';
  static const categoriesWrite = 'categories.write';
  static const merchantsWrite = 'merchants.write';
  static const profileWrite = 'profile.write';
  static const goals = 'goals';
  static const goalsPledges = 'goals.pledges';
  static const rulesWrite = 'rules.write';
  static const accountsWrite = 'accounts.write';
  static const connectionsManage = 'connections.manage';
  static const accountsPermissions = 'accounts.permissions';
  static const accountsLoanRates = 'accounts.loan_rates';

  static const _prefsPrefix = 'server_features:';

  final http.Client? _client;
  Set<String> _features = const {};
  String? _key;
  String? _loadingKey;

  /// True when the current server advertises [feature].
  bool has(String feature) => _features.contains(feature);

  Set<String> get features => Set.unmodifiable(_features);

  /// Called by the provider tree whenever [AuthProvider] changes. Loads the
  /// cached list for the new server + user at once, then refreshes it.
  void updateAuth(AuthProvider auth) {
    // API-key sign-in has no user record, so key the cache on the API key
    // session instead of a user id.
    final userId = auth.user?.id ?? (auth.isApiKeyAuth ? 'api-key' : null);
    if (!auth.isAuthenticated || userId == null) {
      if (_key != null || _features.isNotEmpty) {
        _key = null;
        _features = const {};
        notifyListeners();
      }
      return;
    }
    final key = '${ApiConfig.baseUrl}|$userId';
    if (key == _key || key == _loadingKey) return;
    _loadingKey = key;
    _load(key, auth);
  }

  Future<void> _load(String key, AuthProvider auth) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getStringList('$_prefsPrefix$key');
    if (_loadingKey != key) return;
    _key = key;
    _features = cached?.toSet() ?? const {};
    notifyListeners();
    await refresh(auth);
  }

  /// Fetches the list from the server and caches it. Keeps the last known
  /// list on any failure (offline, 5xx), so a flaky network never hides a
  /// native screen the server does support.
  Future<void> refresh(AuthProvider auth) async {
    final key = _key;
    if (key == null) return;
    try {
      final token = await auth.getValidAccessToken();
      if (token == null) return;
      final client = _client ?? http.Client();
      try {
        final response = await client
            .get(Uri.parse('${ApiConfig.baseUrl}/api/v1/version'),
                headers: ApiConfig.getAuthHeaders(token))
            .timeout(const Duration(seconds: 15));
        if (response.statusCode != 200 || _key != key) return;
        final body = jsonDecode(response.body);
        final list = body is Map<String, dynamic> ? body['features'] : null;
        final next = list is List
            ? list.whereType<String>().toSet()
            : const <String>{};
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('$_prefsPrefix$key', next.toList()..sort());
        if (_key != key) return;
        if (!setEquals(next, _features)) {
          _features = next;
          notifyListeners();
        }
      } finally {
        if (_client == null) client.close();
      }
    } catch (e) {
      LogService.instance.warning(
          'ServerFeatures', 'Feature refresh failed: ${e.runtimeType}');
    } finally {
      if (_loadingKey == key) _loadingKey = null;
    }
  }

  /// Test seam: set the list directly.
  @visibleForTesting
  void debugSet(Set<String> features) {
    _features = features;
    _key ??= 'test';
    notifyListeners();
  }
}
