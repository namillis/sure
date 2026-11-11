import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/account.dart';
import '../services/accounts_service.dart';
import '../services/balance_sheet_service.dart';
import '../services/connectivity_service.dart';
import '../services/log_service.dart';
import '../services/offline_cache_codecs.dart';
import '../services/offline_cache_store.dart';

/// Accounts list and balance sheet for Home.
///
/// Cache first, then network: the last-good accounts and balance sheet for
/// this server + user ([OfflineCacheStore]) are shown at once, then replaced
/// by a fresh load when online. Offline, the cached copy stays on screen.
class AccountsProvider with ChangeNotifier {
  AccountsProvider({
    AccountsService? accountsService,
    BalanceSheetService? balanceSheetService,
    OfflineCacheStore? cache,
    bool Function()? isOnline,
  })  : _accountsService = accountsService ?? AccountsService(),
        _balanceSheetService = balanceSheetService ?? BalanceSheetService(),
        _cacheOverride = cache,
        _isOnlineOverride = isOnline;

  final AccountsService _accountsService;
  final BalanceSheetService _balanceSheetService;
  final OfflineCacheStore? _cacheOverride;
  final bool Function()? _isOnlineOverride;
  final LogService _log = LogService.instance;

  OfflineCacheStore get _cache => _cacheOverride ?? OfflineCacheStore.instance;

  /// Scope the data in memory belongs to; a different one resets it.
  String? _scope;
  DateTime? _lastUpdatedAt;
  bool _isShowingCachedData = false;

  List<Account> _accounts = [];
  bool _isLoading = false;
  bool _isInitializing = true;
  String? _errorMessage;
  Map<String, dynamic>? _pagination;
  ConnectivityService? _connectivityService;

  // Summary / net worth data
  String? _netWorthFormatted;
  String? _assetsFormatted;
  String? _liabilitiesFormatted;
  String? _familyCurrency;
  bool _isBalanceSheetStale = false;

  List<Account> get accounts => _accounts;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
  String? get errorMessage => _errorMessage;
  Map<String, dynamic>? get pagination => _pagination;
  String? get netWorthFormatted => _netWorthFormatted;
  String? get assetsFormatted => _assetsFormatted;
  String? get liabilitiesFormatted => _liabilitiesFormatted;
  String? get familyCurrency => _familyCurrency;
  bool get isBalanceSheetStale => _isBalanceSheetStale;

  /// When the accounts shown were last loaded from the server (from the
  /// cache's save time until a refresh succeeds).
  DateTime? get lastUpdatedAt => _lastUpdatedAt;

  /// True while the accounts shown came from the cache and no refresh has
  /// succeeded since (still loading, offline, or the refresh failed).
  bool get isShowingCachedData => _isShowingCachedData;

  List<Account> get assetAccounts {
    final assets = _accounts.where((a) => a.isAsset).toList();
    _sortAccounts(assets);
    return assets;
  }

  List<Account> get liabilityAccounts {
    final liabilities = _accounts.where((a) => a.isLiability).toList();
    _sortAccounts(liabilities);
    return liabilities;
  }

  Map<String, double> get assetTotalsByCurrency {
    final totals = <String, double>{};
    for (var account in _accounts.where((a) => a.isAsset)) {
      totals[account.currency] =
          (totals[account.currency] ?? 0.0) + account.balanceAsDouble;
    }
    return totals;
  }

  Map<String, double> get liabilityTotalsByCurrency {
    final totals = <String, double>{};
    for (var account in _accounts.where((a) => a.isLiability)) {
      totals[account.currency] =
          (totals[account.currency] ?? 0.0) + account.balanceAsDouble;
    }
    return totals;
  }

  void setConnectivityService(ConnectivityService service) {
    _connectivityService = service;
  }

  void _sortAccounts(List<Account> accounts) {
    accounts.sort((a, b) {
      // 1. Sort by account type
      int typeComparison = a.accountType.compareTo(b.accountType);
      if (typeComparison != 0) return typeComparison;

      // 2. Sort by currency
      int currencyComparison = a.currency.compareTo(b.currency);
      if (currencyComparison != 0) return currencyComparison;

      // 3. Sort by balance (descending - highest first)
      int balanceComparison = b.balanceAsDouble.compareTo(a.balanceAsDouble);
      if (balanceComparison != 0) return balanceComparison;

      // 4. Sort by name
      return a.name.compareTo(b.name);
    });
  }

  /// Cache first, then network. Shows the cached accounts and balance sheet
  /// for this server + user at once (when nothing is in memory yet), then
  /// refreshes from the server whenever online. [forceSync] is kept for
  /// callers; an online call always refreshes.
  Future<bool> fetchAccounts({
    required String accessToken,
    bool forceSync = false,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final scope = await _cache.currentScope();
      if (scope != _scope) {
        // Another server or user: never keep showing the previous one's data.
        _resetData();
        _scope = scope;
      }
      if (scope != null && _accounts.isEmpty) {
        await _loadFromCache(scope);
      }

      final isOnline =
          _isOnlineOverride?.call() ?? _connectivityService?.isOnline ?? false;
      if (isOnline) {
        final result = await _accountsService.getAllAccounts(
          accessToken: accessToken,
        );

        if (result['success'] == true && result.containsKey('accounts')) {
          final serverAccounts =
              (result['accounts'] as List<dynamic>?)?.cast<Account>() ?? [];
          _pagination = result['pagination'] as Map<String, dynamic>?;
          _accounts = serverAccounts;
          _errorMessage = null;
          _isShowingCachedData = false;
          _lastUpdatedAt = scope == null
              ? DateTime.now()
              : await _cache.write(
                  scope,
                  OfflineCacheStore.accountsKey,
                  serverAccounts.map(OfflineCacheCodecs.account).toList(),
                );
        } else if (result['error'] == 'unauthorized') {
          // A revoked session must sign out even when cached data is shown.
          _errorMessage = 'unauthorized';
        } else if (_accounts.isEmpty) {
          // If server fetch failed but we have cached data, that's OK
          _errorMessage =
              result['error'] as String? ?? 'Failed to fetch accounts';
        }

        // Fetch balance sheet independently — works even with cached accounts
        await _fetchBalanceSheet(accessToken, scope);
      } else if (_accounts.isEmpty) {
        _errorMessage =
            'You are offline. Please connect to the internet to load accounts.';
      }

      _isLoading = false;
      _isInitializing = false;
      notifyListeners();
      return _accounts.isNotEmpty;
    } catch (e) {
      _log.error(
        'AccountsProvider',
        'fetchAccounts failed with ${e.runtimeType}',
      );
      // If we have cached accounts, show them even if sync fails
      if (_accounts.isEmpty) {
        // Provide more specific error messages based on exception type
        if (e is SocketException) {
          _errorMessage =
              'Network error. Please check your internet connection and try again.';
        } else if (e is TimeoutException) {
          _errorMessage =
              'Request timed out. Please check your connection and try again.';
        } else if (e is FormatException) {
          _errorMessage = 'Server response error. Please try again later.';
        } else if (e.toString().contains('401') ||
            e.toString().contains('unauthorized')) {
          _errorMessage = 'unauthorized';
        } else if (e.toString().contains('HandshakeException') ||
            e.toString().contains('certificate') ||
            e.toString().contains('SSL')) {
          _errorMessage =
              'Secure connection error. Please check your internet connection and try again.';
        } else {
          _errorMessage = 'Something went wrong. Please try again.';
        }
      }
      _isLoading = false;
      _isInitializing = false;
      notifyListeners();
      return _accounts.isNotEmpty;
    }
  }

  /// Fetches balance sheet data and updates formatted net worth, assets,
  /// and liabilities values for display. On failure, marks the existing
  /// values as stale rather than clearing them.
  Future<void> _fetchBalanceSheet(String accessToken, String? scope) async {
    try {
      final result =
          await _balanceSheetService.getBalanceSheet(accessToken: accessToken);
      if (result['success'] == true) {
        final data = {
          'currency': result['currency'],
          'net_worth': result['net_worth'],
          'assets': result['assets'],
          'liabilities': result['liabilities'],
        };
        _applyBalanceSheet(data);
        _isBalanceSheetStale = false;
        if (scope != null) {
          await _cache.write(scope, OfflineCacheStore.balanceSheetKey, data);
        }
      } else {
        // Keep existing values but mark as stale
        if (_netWorthFormatted != null) {
          _isBalanceSheetStale = true;
        }
      }
    } catch (e) {
      _log.error(
        'AccountsProvider',
        'Balance sheet fetch failed with ${e.runtimeType}',
      );
      // Keep existing values but mark as stale
      if (_netWorthFormatted != null) {
        _isBalanceSheetStale = true;
      }
    }
  }

  void _applyBalanceSheet(Map<String, dynamic> data) {
    String? formatted(Object? section) =>
        section is Map ? section['formatted'] as String? : null;
    _familyCurrency = data['currency'] as String?;
    _netWorthFormatted = formatted(data['net_worth']);
    _assetsFormatted = formatted(data['assets']);
    _liabilitiesFormatted = formatted(data['liabilities']);
  }

  /// Puts the cached accounts and balance sheet on screen, if there are any.
  Future<void> _loadFromCache(String scope) async {
    final accountsEntry =
        await _cache.read(scope, OfflineCacheStore.accountsKey);
    final sheetEntry =
        await _cache.read(scope, OfflineCacheStore.balanceSheetKey);
    // A newer load for another scope may have run meanwhile.
    if (_scope != scope) return;

    final rawAccounts = accountsEntry?.data;
    if (rawAccounts is List) {
      try {
        _accounts = rawAccounts
            .map((a) => Account.fromJson((a as Map).cast<String, dynamic>()))
            .toList();
        _lastUpdatedAt = accountsEntry!.savedAt;
        _isShowingCachedData = true;
      } catch (e) {
        _log.warning(
          'AccountsProvider',
          'Ignoring unreadable cached accounts: ${e.runtimeType}',
        );
        _accounts = [];
      }
    }
    final sheet = sheetEntry?.data;
    if (sheet is Map) _applyBalanceSheet(sheet.cast<String, dynamic>());

    if (_accounts.isNotEmpty) {
      _isInitializing = false;
      notifyListeners();
    }
  }

  void _resetData() {
    _accounts = [];
    _pagination = null;
    _netWorthFormatted = null;
    _assetsFormatted = null;
    _liabilitiesFormatted = null;
    _familyCurrency = null;
    _isBalanceSheetStale = false;
    _lastUpdatedAt = null;
    _isShowingCachedData = false;
  }

  void clearAccounts() {
    _resetData();
    _scope = null;
    _errorMessage = null;
    _isInitializing = true;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
