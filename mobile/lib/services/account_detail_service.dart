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
    bool useSeries = false,
  }) async {
    if (useSeries) {
      return getBalanceSeries(
        accessToken: accessToken,
        accountId: accountId,
        startDate: startDate,
      );
    }
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
    bool stableOrder = false,
  }) {
    return getHoldings(
      accessToken: accessToken,
      accountId: accountId,
      perPage: null,
      stableOrder: stableOrder,
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
  ///
  /// Pass [stableOrder] when the server has `holdings.stable_order` (it then
  /// orders by date and id), so walking pages backwards from the last one is
  /// safe and the extra `?date=` query is skipped.
  Future<Map<String, dynamic>> getHoldings({
    required String accessToken,
    required String accountId,
    int? perPage = 5,
    bool stableOrder = false,
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

      final totalPages = firstPage.totalPages < 1 ? 1 : firstPage.totalPages;
      final lastPage = totalPages == 1
          ? firstPage
          : await _getHoldingsPage(
              accessToken: accessToken,
              accountId: accountId,
              page: totalPages,
            );
      if (!lastPage.success) {
        return _failureFromStatus(lastPage.statusCode, 'Failed to fetch holdings');
      }
      if (lastPage.holdings.isEmpty) {
        return {'success': true, 'holdings': <AccountHolding>[]};
      }

      // The server orders holdings by date only, so rows that share a date
      // come back in an arbitrary order that can change between requests.
      // Walking page boundaries could then repeat one position and skip
      // another, differently on every refresh. Instead: the latest date is
      // the last page's newest row; if that page also holds an older date,
      // every latest-date row is on it (dates themselves are ordered).
      // Otherwise ask for that date alone and drop any repeated row.
      final latest = lastPage.holdings
          .map((h) => h.date)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      final pageHasOlderRow =
          lastPage.holdings.any((h) => !_sameDate(h.date, latest));

      final List<AccountHolding> currentHoldings;
      if (totalPages == 1 || pageHasOlderRow) {
        currentHoldings = lastPage.holdings
            .where((h) => _sameDate(h.date, latest))
            .toList();
      } else if (stableOrder) {
        // Order is (date, id), so the latest-date rows end the list: walk
        // back from the last page until a page starts with an older date.
        currentHoldings = [...lastPage.holdings];
        for (var page = totalPages - 1; page >= 1; page--) {
          final previous = page == 1
              ? firstPage
              : await _getHoldingsPage(
                  accessToken: accessToken,
                  accountId: accountId,
                  page: page,
                );
          if (!previous.success) {
            return _failureFromStatus(
              previous.statusCode,
              'Failed to fetch holdings',
            );
          }
          final onLatest =
              previous.holdings.where((h) => _sameDate(h.date, latest));
          currentHoldings.insertAll(0, onLatest);
          if (previous.holdings.any((h) => !_sameDate(h.date, latest))) break;
        }
      } else {
        currentHoldings = [];
        var page = 1;
        var pages = 1;
        do {
          final datePage = await _getHoldingsPage(
            accessToken: accessToken,
            accountId: accountId,
            page: page,
            date: latest,
          );
          if (!datePage.success) {
            return _failureFromStatus(
              datePage.statusCode,
              'Failed to fetch holdings',
            );
          }
          currentHoldings.addAll(datePage.holdings);
          pages = datePage.totalPages;
          page += 1;
        } while (page <= pages);
      }

      return {
        'success': true,
        'holdings': _topHoldings(_unique(currentHoldings), displayLimit),
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
    DateTime? date,
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/holdings').replace(
      queryParameters: {
        'account_id': accountId,
        'page': page.toString(),
        'per_page': _holdingsPageSize.toString(),
        if (date != null) 'date': DateFormat('yyyy-MM-dd').format(date),
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

  /// One row per holding: by id, else by security (a page boundary under the
  /// server's date-only ordering can return the same row twice).
  List<AccountHolding> _unique(List<AccountHolding> holdings) {
    final seen = <String>{};
    return [
      for (final h in holdings)
        if (seen.add(h.id.isNotEmpty
            ? 'id:${h.id}'
            : 'sec:${h.securityId ?? h.ticker}:${h.accountId}'))
          h,
    ];
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

  /// The series window: the server's own All-time start when [start] is
  /// null, otherwise [start]..[end].
  static Map<String, String> seriesWindow(DateTime? start, DateTime end) {
    final f = DateFormat('yyyy-MM-dd');
    return start == null
        ? {'period': 'all_time'}
        : {'start_date': f.format(start), 'end_date': f.format(end)};
  }

  /// One account's chart from Sure+ `charts.series`
  /// (`GET /api/v1/accounts/:id/balance_series`): one request instead of
  /// paging `/balances`. Returns the same `balances` list shape as
  /// [getBalanceHistory] (oldest first, one row per series point).
  Future<Map<String, dynamic>> getBalanceSeries({
    required String accessToken,
    required String accountId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final now = DateTime.now();
    final end = endDate ?? DateTime(now.year, now.month, now.day);
    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/accounts/'
            '${Uri.encodeComponent(accountId)}/balance_series')
        .replace(queryParameters: seriesWindow(startDate, end));
    try {
      final response = await _client
          .get(url, headers: ApiConfig.getAuthHeaders(accessToken))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        return _failureFromStatus(
            response.statusCode, 'Failed to fetch balances');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': true,
        'balances': seriesBalances(data, idPrefix: accountId),
      };
    } catch (e) {
      _logFailure('getBalanceSeries', e);
      return {
        'success': false,
        'error': 'Unable to load balance history. Please try again later.',
      };
    }
  }

  /// The family's net worth chart from Sure+ `charts.series`
  /// (`GET /api/v1/net_worth_series`). With [etag], a 304 comes back as
  /// `{'success': true, 'notModified': true}`. A 200 gives `data` (the
  /// decoded body) and the new `etag`.
  Future<Map<String, dynamic>> getNetWorthSeries({
    required String accessToken,
    required DateTime? startDate,
    required DateTime endDate,
    String? etag,
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/net_worth_series')
        .replace(queryParameters: seriesWindow(startDate, endDate));
    try {
      final response = await _client.get(url, headers: {
        ...ApiConfig.getAuthHeaders(accessToken),
        if (etag != null) 'If-None-Match': etag,
      }).timeout(const Duration(seconds: 30));
      if (response.statusCode == 304) {
        return {'success': true, 'notModified': true};
      }
      if (response.statusCode != 200) {
        return _failureFromStatus(
            response.statusCode, 'Failed to fetch net worth');
      }
      return {
        'success': true,
        'data': jsonDecode(response.body) as Map<String, dynamic>,
        'etag': response.headers['etag'],
      };
    } catch (e) {
      _logFailure('getNetWorthSeries', e);
      return {
        'success': false,
        'error': 'Unable to load net worth. Please try again later.',
      };
    }
  }

  /// A chart-series body's `values` as balance rows, oldest first.
  static List<AccountBalance> seriesBalances(
    Map<String, dynamic> data, {
    required String idPrefix,
  }) {
    final currency = data['currency']?.toString() ?? '';
    final values = data['values'];
    if (values is! List) return const [];
    return [
      for (final v in values)
        if (v is Map && DateTime.tryParse(v['date']?.toString() ?? '') != null)
          AccountBalance(
            id: '$idPrefix-${v['date']}',
            date: DateTime.parse(v['date'].toString()),
            currency: currency,
            balance: v['value']?.toString() ?? '',
            balanceCents: JsonParsing.parseInt(v['value_cents']),
          ),
    ];
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
