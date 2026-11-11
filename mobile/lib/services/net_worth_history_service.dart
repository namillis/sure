import '../models/account.dart';
import '../models/account_balance.dart';
import '../utils/net_worth_history.dart';
import 'account_detail_service.dart';

/// Loads [NetWorthHistory] for a period by fetching each main-currency
/// asset and liability account's daily balances from `GET /api/v1/balances`
/// (via [AccountDetailService.getBalanceHistory]) and summing them on the
/// phone. The server has no net worth history endpoint.
class NetWorthHistoryService {
  NetWorthHistoryService({AccountDetailService? accountDetailService})
      : _service = accountDetailService ?? AccountDetailService(),
        _ownsService = accountDetailService == null;

  final AccountDetailService _service;
  final bool _ownsService;

  /// Accounts fetched at once.
  static const int maxConcurrent = 4;

  void close() {
    if (_ownsService) _service.close();
  }

  /// Returns `{'success': true, 'history': NetWorthHistory}` or
  /// `{'success': false, 'error': …}` (`'unauthorized'` on 401). Any failed
  /// account fails the whole load, since a partial sum would be wrong.
  ///
  /// Accounts outside [mainCurrency] are not fetched; their current balances
  /// are totaled per currency instead.
  Future<Map<String, dynamic>> load({
    required String accessToken,
    required List<Account> accounts,
    required String mainCurrency,
    required DateTime start,
    required DateTime end,
  }) async {
    final relevant =
        accounts.where((a) => a.isAsset || a.isLiability).toList();
    final toFetch =
        relevant.where((a) => a.currency == mainCurrency).toList();

    final balances = <String, List<AccountBalance>>{};
    String? error;
    var next = 0;
    Future<void> worker() async {
      while (error == null && next < toFetch.length) {
        final account = toFetch[next++];
        final result = await _service.getBalanceHistory(
          accessToken: accessToken,
          accountId: account.id,
          startDate: start,
        );
        if (result['success'] == true) {
          balances[account.id] =
              (result['balances'] as List).cast<AccountBalance>();
        } else {
          // Unauthorized wins over other errors so the caller signs out.
          final e = result['error']?.toString() ?? 'Failed to fetch balances';
          if (error != 'unauthorized') error = e;
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < maxConcurrent && i < toFetch.length; i++) worker(),
    ]);
    if (error != null) return {'success': false, 'error': error};

    return {
      'success': true,
      'history': NetWorthHistory.build(
        accounts: [
          for (final account in relevant)
            NetWorthAccountHistory(
              accountId: account.id,
              currency: account.currency,
              isLiability: account.isLiability,
              currentCents: account.balanceCents,
              balances: balances[account.id] ?? const [],
            ),
        ],
        mainCurrency: mainCurrency,
        start: start,
        end: end,
      ),
    };
  }
}
