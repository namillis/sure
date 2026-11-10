import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../models/account.dart';
import '../models/account_balance.dart';
import '../models/account_holding.dart';
import '../models/account_trade.dart';
import '../utils/json_parsing.dart';
import 'api_config.dart';
import 'log_service.dart';

class AccountDetailService {
  static const int _holdingsPageSize = 100;
  static const int _balancesPageSize = 100;

  final http.Client _client;
  final bool _ownsClient;

  AccountDetailService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  Future<Map<String, dynamic>> getAccountDetail({
    required String accessToken,
    required String accountId,
  }) async {
    final accountPathId = Uri.encodeComponent(accountId);
    final url =
        Uri.parse('${ApiConfig.baseUrl}/api/v1/accounts/$accountPathId');

    try {
      final response = await _client
          .get(url, headers: ApiConfig.getAuthHeaders(accessToken))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return {
          'success': true,
          'account': Account.fromJson(jsonDecode(response.body)),
        };
      }

      return _failureFromStatus(response.statusCode, 'Failed to fetch account');
    } catch (e) {
      _logFailure('getAccountDetail', e);
      return {
        'success': false,
        'error': 'Unable to load account details. Please try again later.',
      };
    }
  }

  Future<Map<String, dynamic>> getBalances({
    required String accessToken,
    required String accountId,
    int perPage = 30,
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/balances').replace(
      queryParameters: {
        'account_id': accountId,
        'per_page': perPage.toString(),
      },
    );

    try {
      final response = await _client
          .get(url, headers: ApiConfig.getAuthHeaders(accessToken))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        final balances = (responseData['balances'] as List<dynamic>? ?? [])
            .map(
              (json) => AccountBalance.fromJson(json as Map<String, dynamic>),
            )
            .toList();

        return {'success': true, 'balances': balances};
      }

      return _failureFromStatus(
        response.statusCode,
        'Failed to fetch balances',
      );
    } catch (e) {
      _logFailure('getBalances', e);
      return {
        'success': false,
        'error': 'Unable to load balance history. Please try again later.',
      };
    }
  }

  /// Daily balances for [accountId] on or after [startDate] (all history when
  /// null), oldest first. Walks every page up to [maxPages] of 100.
  Future<Map<String, dynamic>> getBalanceHistory({
    required String accessToken,
    required String accountId,
    DateTime? startDate,
    int maxPages = 40,
  }) async {
    Uri pageUrl(int page) =>
        Uri.parse('${ApiConfig.baseUrl}/api/v1/balances').replace(
          queryParameters: {
            'account_id': accountId,
            'page': page.toString(),
            'per_page': _balancesPageSize.toString(),
            if (startDate != null)
              'start_date': DateFormat('yyyy-MM-dd').format(startDate),
          },
        );

    Future<http.Response> fetch(int page) => _client
        .get(pageUrl(page), headers: ApiConfig.getAuthHeaders(accessToken))
        .timeout(const Duration(seconds: 30));

    List<AccountBalance> parse(http.Response response) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['balances'] as List<dynamic>? ?? [])
          .map((json) => AccountBalance.fromJson(json as Map<String, dynamic>))
          .toList();
    }

    try {
      final first = await fetch(1);
      if (first.statusCode != 200) {
        return _failureFromStatus(
            first.statusCode, 'Failed to fetch balances');
      }

      final balances = parse(first);
      final pagination =
          (jsonDecode(first.body) as Map<String, dynamic>)['pagination']
              as Map<String, dynamic>?;
      final totalPages =
          (JsonParsing.parseInt(pagination?['total_pages']) ?? 1)
              .clamp(1, maxPages)
              .toInt();

      if (totalPages > 1) {
        final rest = await Future.wait([
          for (var page = 2; page <= totalPages; page++) fetch(page),
        ]);
        for (final response in rest) {
          if (response.statusCode != 200) {
            return _failureFromStatus(
                response.statusCode, 'Failed to fetch balances');
          }
          balances.addAll(parse(response));
        }
      }

      // The API returns newest first; charts want oldest first.
      balances.sort((left, right) => left.date.compareTo(right.date));
      return {'success': true, 'balances': balances};
    } catch (e) {
      _logFailure('getBalanceHistory', e);
      return {
        'success': false,
        'error': 'Unable to load balance history. Please try again later.',
      };
    }
  }

  /// Every position on the account's latest holdings date, largest first.
  Future<Map<String, dynamic>> getCurrentHoldings({
    required String accessToken,
    required String accountId,
  }) {
    return getHoldings(
      accessToken: accessToken,
      accountId: accountId,
      perPage: null,
    );
  }

  /// One page of investment activity, newest first: for [accountId], or across
  /// [accountIds] when that is given instead.
  Future<Map<String, dynamic>> getTrades({
    required String accessToken,
    String? accountId,
    List<String>? accountIds,
    int page = 1,
    int perPage = 25,
  }) async {
    assert(
      (accountId == null) != (accountIds == null),
      'Pass exactly one of accountId or accountIds.',
    );
    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/trades').replace(
      queryParameters: <String, dynamic>{
        if (accountId != null) 'account_id': accountId,
        // Rails reads repeated `account_ids[]` keys as an array.
        if (accountIds != null) 'account_ids[]': accountIds,
        'page': page.toString(),
        'per_page': perPage.toString(),
      },
    );

    try {
      final response = await _client
          .get(url, headers: ApiConfig.getAuthHeaders(accessToken))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return _failureFromStatus(response.statusCode, 'Failed to fetch trades');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final trades = (data['trades'] as List<dynamic>? ?? [])
          .map((json) => AccountTrade.fromJson(json as Map<String, dynamic>))
          .toList();
      final pagination = data['pagination'] as Map<String, dynamic>?;
      final totalPages = JsonParsing.parseInt(pagination?['total_pages']) ?? 1;

      return {
        'success': true,
        'trades': trades,
        'hasMore': page < totalPages,
      };
    } catch (e) {
      _logFailure('getTrades', e);
      return {
        'success': false,
        'error': 'Unable to load investment activity. Please try again later.',
      };
    }
  }

  /// Positions on the latest holdings date, largest first. [perPage] caps how
  /// many are returned; null returns all of them.
  Future<Map<String, dynamic>> getHoldings({
    required String accessToken,
    required String accountId,
    int? perPage = 5,
  }) async {
    final displayLimit = perPage?.clamp(1, _holdingsPageSize).toInt();

    try {
      final firstPage = await _getHoldingsPage(
        accessToken: accessToken,
        accountId: accountId,
        page: 1,
      );

      if (!firstPage.success) {
        return _failureFromStatus(
          firstPage.statusCode,
          'Failed to fetch holdings',
        );
      }

      final currentHoldings = <AccountHolding>[];
      DateTime? currentDate;
      final totalPages = firstPage.totalPages < 1 ? 1 : firstPage.totalPages;

      // Holdings are chronological, so the latest positions are at the end of
      // the final page. Walk backward only until the date changes; this keeps
      // the common case to page 1 + latest page while still handling accounts
      // whose current positions span a page boundary.
      for (var page = totalPages; page >= 1; page -= 1) {
        final holdingsPage = page == 1
            ? firstPage
            : await _getHoldingsPage(
                accessToken: accessToken,
                accountId: accountId,
                page: page,
              );

        if (!holdingsPage.success) {
          return _failureFromStatus(
            holdingsPage.statusCode,
            'Failed to fetch holdings',
          );
        }

        for (final holding in holdingsPage.holdings.reversed) {
          currentDate ??= holding.date;
          if (!_sameDate(holding.date, currentDate)) {
            return {
              'success': true,
              'holdings': _topHoldings(currentHoldings, displayLimit),
            };
          }
          currentHoldings.add(holding);
        }
      }

      return {
        'success': true,
        'holdings': _topHoldings(currentHoldings, displayLimit),
      };
    } catch (e) {
      _logFailure('getHoldings', e);
      return {
        'success': false,
        'error': 'Unable to load holdings. Please try again later.',
      };
    }
  }

  Future<_HoldingsPage> _getHoldingsPage({
    required String accessToken,
    required String accountId,
    required int page,
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/holdings').replace(
      queryParameters: {
        'account_id': accountId,
        'page': page.toString(),
        'per_page': _holdingsPageSize.toString(),
      },
    );

    final response = await _client
        .get(url, headers: ApiConfig.getAuthHeaders(accessToken))
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      return _HoldingsPage.failure(response.statusCode);
    }

    final responseData = jsonDecode(response.body) as Map<String, dynamic>;
    final holdings = (responseData['holdings'] as List<dynamic>? ?? [])
        .map(
          (json) => AccountHolding.fromJson(json as Map<String, dynamic>),
        )
        .toList();
    final pagination = responseData['pagination'] as Map<String, dynamic>?;
    final totalPages = JsonParsing.parseInt(pagination?['total_pages']) ?? 1;

    return _HoldingsPage.success(
      holdings: holdings,
      totalPages: totalPages,
    );
  }

  List<AccountHolding> _topHoldings(
    List<AccountHolding> holdings,
    int? displayLimit,
  ) {
    final sorted = holdings.toList()
      ..sort(
        (left, right) =>
            _amountValue(right.amount).compareTo(_amountValue(left.amount)),
      );
    return displayLimit == null
        ? sorted
        : sorted.take(displayLimit).toList();
  }

  double _amountValue(String amount) {
    final numeric = amount.replaceAll(RegExp(r'[^\d.-]'), '');
    return double.tryParse(numeric) ?? 0;
  }

  bool _sameDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  Map<String, dynamic> _failureFromStatus(int statusCode, String fallback) {
    if (statusCode == 401) {
      return {'success': false, 'error': 'unauthorized'};
    }

    return {'success': false, 'error': fallback};
  }

  void _logFailure(String operation, Object error) {
    LogService.instance.error(
      'AccountDetailService',
      '$operation failed with ${error.runtimeType}',
    );
  }
}

class _HoldingsPage {
  final bool success;
  final int statusCode;
  final List<AccountHolding> holdings;
  final int totalPages;

  _HoldingsPage.success({
    required this.holdings,
    required this.totalPages,
  })  : success = true,
        statusCode = 200;

  _HoldingsPage.failure(this.statusCode)
      : success = false,
        holdings = const [],
        totalPages = 1;
}
