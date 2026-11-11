import 'package:flutter/foundation.dart';
import 'package:sure_mobile/models/account.dart';
import 'package:sure_mobile/providers/accounts_provider.dart';
import 'package:sure_mobile/providers/auth_provider.dart';
import 'package:sure_mobile/services/connectivity_service.dart';

/// An [AccountsProvider] with fixed state that never touches the network.
class FakeAccountsProvider extends AccountsProvider {
  FakeAccountsProvider({
    List<Account>? accounts,
    this.netWorth,
    this.currency = 'USD',
    this.updatedAt,
    this.cached = false,
    this.stale = false,
    this.error,
  }) : _accountsList = accounts ?? const [];

  final List<Account> _accountsList;
  final String? netWorth;
  final String currency;
  final DateTime? updatedAt;
  final bool cached;
  final bool stale;
  final String? error;
  int fetches = 0;

  @override
  List<Account> get accounts => _accountsList;
  @override
  String? get netWorthFormatted => netWorth;
  @override
  String? get familyCurrency => currency;
  @override
  bool get isInitializing => false;
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => error;
  @override
  DateTime? get lastUpdatedAt => updatedAt;
  @override
  bool get isShowingCachedData => cached;
  @override
  bool get isBalanceSheetStale => stale;

  @override
  Future<bool> fetchAccounts({
    required String accessToken,
    bool forceSync = false,
  }) async {
    fetches++;
    return _accountsList.isNotEmpty;
  }
}

class FakeConnectivity extends ChangeNotifier implements ConnectivityService {
  FakeConnectivity({this.offline = false});

  bool offline;

  @override
  bool get isOnline => !offline;
  @override
  bool get isOffline => offline;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuth extends ChangeNotifier implements AuthProvider {
  int logouts = 0;

  @override
  Future<String?> getValidAccessToken() async => 'token';
  @override
  Future<void> logout() async => logouts++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Account homeAccount(
  String id, {
  String name = '',
  String type = 'depository',
  String classification = 'asset',
  String currency = 'USD',
  required String balance,
  int? cents,
  String? institution,
}) =>
    Account(
      id: id,
      name: name.isEmpty ? id : name,
      balance: balance,
      balanceCents: cents,
      currency: currency,
      accountType: type,
      classification: classification,
      institutionName: institution,
    );
