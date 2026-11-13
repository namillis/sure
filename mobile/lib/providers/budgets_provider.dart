import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/budget.dart';
import '../services/budgets_service.dart';
import '../services/log_service.dart';
import '../services/offline_cache_codecs.dart';
import '../services/offline_cache_store.dart';

/// Why a month could not be shown.
enum BudgetsLoadError { offline, unauthorized, failed }

/// State for the Budgets screen: the selected month, the budget(s) the server
/// has for it, and each category line with its actual spending.
///
/// The budgets API's list endpoints leave out actual
/// amounts, so a month is assembled from the budget list (to find the month's
/// budget), the budget's show endpoint (totals) and one show request per
/// budget category (actual / remaining). Months already loaded in this session
/// are kept in memory, so flipping back is instant and still works offline.
///
/// Each loaded month is also saved to [OfflineCacheStore] for this server +
/// user. A month not in memory is first read from there and shown at once,
/// then refreshed when online; offline it stays on screen.
class BudgetsProvider with ChangeNotifier {
  BudgetsProvider({
    BudgetsService? service,
    DateTime Function()? clock,
    bool Function()? isOffline,
    OfflineCacheStore? cache,
  })  : _service = service ?? BudgetsService(),
        _clock = clock ?? DateTime.now,
        _isOffline = isOffline ?? (() => false),
        _cacheOverride = cache {
    _month = _firstOfMonth(_clock());
  }

  final BudgetsService _service;
  final DateTime Function() _clock;
  final bool Function() _isOffline;
  final OfflineCacheStore? _cacheOverride;
  final LogService _log = LogService.instance;

  OfflineCacheStore get _store => _cacheOverride ?? OfflineCacheStore.instance;
  Future<String?>? _scopeFuture;
  Future<String?> _cacheScope() => _scopeFuture ??= _store.currentScope();

  /// Months in [_cache] that came from disk and haven't been refreshed yet.
  final Set<String> _fromDisk = {};
  bool _triedCachedPeriod = false;

  /// Concurrent per-category requests while assembling a month.
  static const int _categoryConcurrency = 6;
  static const int _perPage = 100;

  /// Safety stop for a server that keeps reporting more pages (10,000 lines).
  static const int _maxCategoryPages = 100;

  late DateTime _month;
  final Map<String, _MonthData> _cache = {};
  final Map<String, String> _selectedBudgetByMonth = {};
  bool _isLoading = false;
  BudgetsLoadError? _error;
  bool _showingCachedWhileOffline = false;
  int _generation = 0;
  bool _isDisposed = false;

  /// First month of the budget period that contains today. For a family whose
  /// month starts on, say, the 15th, on October 10 that is September. Starts
  /// as the calendar month and is corrected by the first successful load.
  late DateTime _currentPeriodMonth = _firstOfMonth(_clock());
  bool _currentPeriodResolved = false;

  /// First day of the month being shown.
  DateTime get month => _month;

  /// Now, from the injected clock (for "19 days left").
  DateTime get today => _clock();
  bool get isLoading => _isLoading;
  BudgetsLoadError? get error => _error;

  /// True when the device is offline and the month shown came from memory.
  bool get showingCachedWhileOffline => _showingCachedWhileOffline;

  _MonthData? get _current => _cache[_monthKey(_month)];

  /// Whether the server returned a budget list for the month (possibly empty).
  bool get hasLoadedMonth => _current != null;

  /// A refresh failed but an earlier load of this month is still held, so the
  /// screen can keep showing it instead of replacing it with an error page.
  bool get refreshFailed => _error == BudgetsLoadError.failed && hasLoadedMonth;

  /// All budgets visible to the user for this month: the household budget
  /// plus any personal or shared ones.
  List<Budget> get monthBudgets => _current?.budgets ?? const [];

  Budget? get budget => _current?.selected;

  List<BudgetCategory> get categories => _current?.categories ?? const [];

  /// True while the selected budget is not initialized yet: the web page then
  /// shows every category rather than only the budgeted ones.
  bool get showsAllCategories => budget != null && !budget!.initialized;

  List<BudgetCategory>? _visibleGroupsSource;
  bool? _visibleGroupsShowAll;
  List<BudgetCategoryGroup> _visibleGroups = const [];

  /// Parent categories with their subcategories, limited to the lines the web
  /// budget page shows (budgeted, or with spending). Rebuilt only when the
  /// month's categories change.
  List<BudgetCategoryGroup> get visibleGroups {
    final source = categories;
    if (identical(source, _visibleGroupsSource) &&
        _visibleGroupsShowAll == showsAllCategories) {
      return _visibleGroups;
    }
    _visibleGroupsSource = source;
    _visibleGroupsShowAll = showsAllCategories;
    return _visibleGroups = _buildVisibleGroups();
  }

  List<BudgetCategoryGroup> _buildVisibleGroups() {
    final groups = BudgetCategoryGroup.build(categories);
    // Web: `budget.initialized? ? visible_on_track? : true`. A budget that
    // hasn't been set up yet lists every category so it can be configured.
    if (showsAllCategories) return groups;
    final visible = <BudgetCategoryGroup>[];
    for (final group in groups) {
      final children = group.children.where((c) => c.isVisible).toList();
      if (group.parent.isVisible || children.isNotEmpty) {
        visible.add(
          BudgetCategoryGroup(parent: group.parent, children: children),
        );
      }
    }
    return visible;
  }

  /// Number of visible category lines (parents and subcategories) that are
  /// over budget.
  int get overBudgetCount {
    var count = 0;
    for (final group in visibleGroups) {
      if (group.parent.isOverBudget) count++;
      count += group.children.where((c) => c.isOverBudget).length;
    }
    return count;
  }

  /// The server accepts budgets up to two years past the current period
  /// (web: `Budget.latest_valid_budget_start_date`), so planned future months
  /// stay reachable.
  bool get canGoNext => _month.isBefore(
        DateTime(_currentPeriodMonth.year + 2, _currentPeriodMonth.month),
      );

  void previousMonth() => _setMonth(DateTime(_month.year, _month.month - 1));

  void nextMonth() {
    if (canGoNext) _setMonth(DateTime(_month.year, _month.month + 1));
  }

  void _setMonth(DateTime month) {
    // A load still running for the previous month must not clear the spinner
    // or set an error on the month now shown (its result is still cached
    // under its own month).
    _generation++;
    _isLoading = false;
    _month = _firstOfMonth(month);
    _error = null;
    _showingCachedWhileOffline = false;
    notifyListeners();
  }

  /// Switch between budgets when the month has more than one.
  Future<void> selectBudget({
    required String accessToken,
    required String budgetId,
  }) async {
    final key = _monthKey(_month);
    if (_cache[key]?.selected?.id == budgetId) return;
    _selectedBudgetByMonth[key] = budgetId;
    // The month's budget list is already known; only the chosen budget's
    // detail and categories need fetching.
    await _loadMonth(
      accessToken: accessToken,
      forceRefresh: true,
      knownBudgets: _cache[key]?.budgets,
      knownBudgetsMonthKey: key,
    );
  }

  /// Shows the session-expired state, e.g. when no access token is available.
  void markUnauthorized() {
    _generation++;
    _isLoading = false;
    _error = BudgetsLoadError.unauthorized;
    _showingCachedWhileOffline = false;
    notifyListeners();
  }

  /// Budgets the server refused to change with 403 `forbidden` (shared with
  /// this user read-only), for servers without `budgets.permissions`, whose
  /// budget JSON has no `can_edit`.
  final Set<String> _readOnlyBudgetIds = {};

  /// The shown budget is shared with the user read-only: its `can_edit` is
  /// false, or a write was refused with 403 `forbidden`.
  bool get isReadOnly {
    final b = budget;
    if (b == null) return false;
    return b.canEdit == false || _readOnlyBudgetIds.contains(b.id);
  }

  /// Moves [amount] of [from]'s allocation to [to] (Sure+
  /// `budgets.allocations`), then reloads the month. Returns the service
  /// result.
  Future<Map<String, dynamic>> moveAllocation({
    required String accessToken,
    required BudgetCategory from,
    required BudgetCategory to,
    required String amount,
  }) async {
    final result = await _service.moveAllocation(
      accessToken: accessToken,
      budgetId: from.budgetId,
      fromId: from.id,
      toId: to.id,
      amount: amount,
    );
    _afterWrite(result, accessToken: accessToken, budgetId: from.budgetId);
    return result;
  }

  /// Copies the most recent set-up month into the shown month (Sure+
  /// `budgets.allocations`). Reloads the month on success and on 409
  /// `already_set_up`. Returns the service result.
  Future<Map<String, dynamic>> copyPreviousMonth({
    required String accessToken,
    required String monthParam,
  }) async {
    final result = await _service.copyPreviousMonth(
      accessToken: accessToken,
      monthParam: monthParam,
    );
    final reload =
        result['success'] == true || result['code'] == 'already_set_up';
    if (!_isDisposed && reload) {
      await loadMonth(accessToken: accessToken, forceRefresh: true);
    }
    return result;
  }

  /// Sets up the shown month with empty amounts (Sure+
  /// `budgets.allocations`), then loads it. Returns the service result.
  Future<Map<String, dynamic>> startMonth({required String accessToken}) async {
    final result =
        await _service.startMonth(accessToken: accessToken, month: _month);
    if (!_isDisposed && result['success'] == true) {
      await loadMonth(accessToken: accessToken, forceRefresh: true);
    }
    return result;
  }

  /// Saves the totals of the shown budget (Sure+ `budgets.write`), then
  /// reloads the month. Returns the service result.
  Future<Map<String, dynamic>> updateBudget({
    required String accessToken,
    required String budgetId,
    String? budgetedSpending,
    String? expectedIncome,
  }) async {
    final result = await _service.updateBudget(
      accessToken: accessToken,
      id: budgetId,
      budgetedSpending: budgetedSpending,
      expectedIncome: expectedIncome,
    );
    _afterWrite(result, accessToken: accessToken, budgetId: budgetId);
    return result;
  }

  /// Saves one category line (Sure+ `budgets.write`), then reloads the month
  /// so a re-synced parent and recomputed rollover show. Returns the service
  /// result.
  Future<Map<String, dynamic>> updateBudgetCategory({
    required String accessToken,
    required BudgetCategory budgetCategory,
    String? budgetedSpending,
    bool? rolloverEnabled,
  }) async {
    final result = await _service.updateBudgetCategory(
      accessToken: accessToken,
      id: budgetCategory.id,
      budgetedSpending: budgetedSpending,
      rolloverEnabled: rolloverEnabled,
    );
    _afterWrite(
      result,
      accessToken: accessToken,
      budgetId: budgetCategory.budgetId,
    );
    return result;
  }

  void _afterWrite(
    Map<String, dynamic> result, {
    required String accessToken,
    required String budgetId,
  }) {
    if (_isDisposed) return;
    if (result['success'] == true) {
      unawaited(loadMonth(accessToken: accessToken, forceRefresh: true));
    } else if (result['code'] == 'forbidden') {
      _readOnlyBudgetIds.add(budgetId);
      notifyListeners();
    }
  }

  /// Loads the selected month. Uses the in-memory copy unless [forceRefresh].
  Future<void> loadMonth({
    required String accessToken,
    bool forceRefresh = false,
  }) =>
      _loadMonth(accessToken: accessToken, forceRefresh: forceRefresh);

  Future<void> _loadMonth({
    required String accessToken,
    bool forceRefresh = false,
    List<Budget>? knownBudgets,
    String? knownBudgetsMonthKey,
  }) async {
    if (!_currentPeriodResolved && !_isOffline()) {
      // Show the spinner while the current period resolves; every branch
      // below resets the flag or re-sets it for the month fetch.
      _isLoading = true;
      _error = null;
      notifyListeners();
      await _resolveCurrentPeriod(accessToken);
    } else if (!_currentPeriodResolved && !_triedCachedPeriod) {
      _triedCachedPeriod = true;
      await _applyCachedCurrentPeriod();
    }
    final key = _monthKey(_month);
    final month = _month;
    final generation = ++_generation;
    // Resolving the current period above can move [_month]; a budget list
    // captured for another month must not be reused for this one.
    if (knownBudgetsMonthKey != key) knownBudgets = null;

    if (!_cache.containsKey(key)) {
      final saved = await _readMonth(key);
      if (_isDisposed) return;
      if (saved != null && !_cache.containsKey(key)) {
        _cache[key] = saved;
        _fromDisk.add(key);
      }
      if (generation != _generation) return;
    }

    if (_isOffline()) {
      _showingCachedWhileOffline = _cache.containsKey(key);
      _error = _showingCachedWhileOffline ? null : BudgetsLoadError.offline;
      _isLoading = false;
      notifyListeners();
      return;
    }

    if (!forceRefresh && _cache.containsKey(key) && !_fromDisk.contains(key)) {
      // A superseded request for another month can't clear this any more.
      _isLoading = false;
      _showingCachedWhileOffline = false;
      _error = null;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    _showingCachedWhileOffline = false;
    notifyListeners();

    try {
      final data = await _fetchMonth(
        accessToken,
        month,
        knownBudgets: knownBudgets,
      );
      if (_isDisposed) return;
      if (generation != _generation) {
        // Superseded (the user moved to another month). The data is complete
        // for its own month, so keep it unless a newer load already did; the
        // UI state belongs to the latest load.
        if (!_cache.containsKey(key) || _fromDisk.contains(key)) {
          _storeMonth(key, data);
        }
        return;
      }
      _storeMonth(key, data);
      _log.info(
        'BudgetsProvider',
        'Loaded ${data.budgets.length} budget(s), '
            '${data.categories.length} categories for $key',
      );
    } on _BudgetsFetchException catch (e) {
      if (generation != _generation) return;
      // The raw error (server message, network exception text) is logged,
      // not shown: the screen shows its own localized failure message.
      _error = e.error;
      _log.error('BudgetsProvider', 'Failed to load budgets for $key: $e');
    } catch (e) {
      if (generation != _generation) return;
      _error = BudgetsLoadError.failed;
      _log.error('BudgetsProvider', 'Exception loading budgets for $key: $e');
    } finally {
      if (generation == _generation) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Finds the budget whose period contains today and, if the user hasn't
  /// navigated yet, opens on it. Without one (no budget yet, or a failed
  /// request) the screen stays on the calendar month.
  Future<void> _resolveCurrentPeriod(String accessToken) async {
    final today = _clock();
    final day = DateTime(today.year, today.month, today.day);
    final initialMonth = _firstOfMonth(today);
    try {
      final result = await _service.getBudgets(
        accessToken: accessToken,
        startDate: DateTime(initialMonth.year, initialMonth.month - 1),
        endDate: DateTime(initialMonth.year, initialMonth.month + 2, 0),
        perPage: _perPage,
      );
      if (result['success'] != true) return;
      _currentPeriodResolved = true;
      final budgets = result['budgets'] as List<Budget>;
      // The server knows the family's date (`current`); the device's
      // calendar can be a day off near a period boundary. The local date
      // is only a fallback for servers that don't send the flag.
      Budget? current;
      for (final b in budgets) {
        if (b.current) {
          current = b;
          break;
        }
      }
      if (current == null) {
        for (final b in budgets) {
          if (!b.startDate.isAfter(day) && !b.endDate.isBefore(day)) {
            current = b;
            break;
          }
        }
      }
      if (current != null) {
        _currentPeriodMonth = _firstOfMonth(current.startDate);
        if (_month == initialMonth) _month = _currentPeriodMonth;
        final scope = await _cacheScope();
        if (scope != null) {
          await _store.write(
            scope,
            OfflineCacheStore.budgetsCurrentPeriodKey,
            {'month': _monthKey(_currentPeriodMonth)},
          );
        }
      }
    } catch (e) {
      _log.error('BudgetsProvider', 'Could not resolve current period: $e');
    }
  }

  /// Offline before the current period resolved: open on the period saved by
  /// an earlier online load, so a custom month start still lands right.
  Future<void> _applyCachedCurrentPeriod() async {
    final scope = await _cacheScope();
    if (scope == null) return;
    final entry =
        await _store.read(scope, OfflineCacheStore.budgetsCurrentPeriodKey);
    final data = entry?.data;
    final saved = data is Map ? _parseMonthKey(data['month']) : null;
    if (saved == null) return;
    final initialMonth = _firstOfMonth(_clock());
    _currentPeriodMonth = saved;
    if (_month == initialMonth) _month = saved;
  }

  /// Keeps [data] in memory and saves it for the next launch.
  void _storeMonth(String key, _MonthData data) {
    _cache[key] = data;
    _fromDisk.remove(key);
    unawaited(_writeMonth(key, data));
  }

  Future<void> _writeMonth(String key, _MonthData data) async {
    final scope = await _cacheScope();
    if (scope == null) return;
    await _store.write(scope, OfflineCacheStore.budgetsMonthKey(key), {
      'budgets': data.budgets.map(OfflineCacheCodecs.budget).toList(),
      'selected':
          data.selected == null ? null : OfflineCacheCodecs.budget(data.selected!),
      'categories':
          data.categories.map(OfflineCacheCodecs.budgetCategory).toList(),
    });
  }

  Future<_MonthData?> _readMonth(String key) async {
    final scope = await _cacheScope();
    if (scope == null) return null;
    final entry =
        await _store.read(scope, OfflineCacheStore.budgetsMonthKey(key));
    final data = entry?.data;
    if (data is! Map) return null;
    try {
      Map<String, dynamic> map(Object? o) => (o as Map).cast<String, dynamic>();
      final selected = data['selected'];
      return _MonthData(
        budgets: [
          for (final b in data['budgets'] as List) Budget.fromJson(map(b)),
        ],
        selected: selected == null ? null : Budget.fromJson(map(selected)),
        categories: [
          for (final c in data['categories'] as List)
            BudgetCategory.fromJson(map(c)),
        ],
      );
    } catch (e) {
      _log.warning('BudgetsProvider', 'Ignoring unreadable cached month $key');
      return null;
    }
  }

  Future<_MonthData> _fetchMonth(
    String accessToken,
    DateTime month, {
    List<Budget>? knownBudgets,
  }) async {
    if (knownBudgets != null) {
      return _fetchSelected(accessToken, month, knownBudgets);
    }
    // A family with a custom month start has budgets that begin mid-month and
    // end in the next one, so widen the window and match on the start month.
    final listResult = await _service.getBudgets(
      accessToken: accessToken,
      startDate: month,
      endDate: DateTime(month.year, month.month + 2, 0),
      perPage: _perPage,
    );
    _throwIfFailed(listResult);

    final budgets = (listResult['budgets'] as List<Budget>)
        .where(
          (b) =>
              b.startDate.year == month.year &&
              b.startDate.month == month.month,
        )
        .toList();

    return _fetchSelected(accessToken, month, budgets);
  }

  Future<_MonthData> _fetchSelected(
    String accessToken,
    DateTime month,
    List<Budget> budgets,
  ) async {
    if (budgets.isEmpty) {
      return _MonthData(budgets: budgets);
    }

    final key = _monthKey(month);
    final preferredId = _selectedBudgetByMonth[key];
    final summary = budgets.firstWhere(
      (b) => b.id == preferredId,
      orElse: () => budgets.first,
    );

    final results = await Future.wait([
      _service.getBudget(accessToken: accessToken, id: summary.id),
      _fetchAllCategories(accessToken, summary.id),
    ]);

    final budgetResult = results[0] as Map<String, dynamic>;
    _throwIfFailed(budgetResult);
    final detailed = budgetResult['budget'] as Budget;

    final indexCategories = results[1] as List<BudgetCategory>;
    final categories = await _withDerivedAmounts(accessToken, indexCategories);

    return _MonthData(
      budgets: budgets,
      selected: detailed,
      categories: categories,
    );
  }

  Future<List<BudgetCategory>> _fetchAllCategories(
    String accessToken,
    String budgetId,
  ) async {
    final all = <BudgetCategory>[];
    var page = 1;
    while (true) {
      final result = await _service.getBudgetCategories(
        accessToken: accessToken,
        budgetId: budgetId,
        page: page,
        perPage: _perPage,
      );
      _throwIfFailed(result);
      all.addAll(result['budget_categories'] as List<BudgetCategory>);

      final pagination = result['pagination'] as Map<String, dynamic>?;
      final totalPages = (pagination?['total_pages'] as num?)?.toInt() ?? 1;
      if (page >= totalPages) break;
      if (page >= _maxCategoryPages) {
        // Never cache a truncated month as if it were complete.
        throw const _BudgetsFetchException(
          BudgetsLoadError.failed,
          'too many budget category pages',
        );
      }
      page++;
    }
    return all;
  }

  /// Replaces each index record with its show record (which carries actual
  /// spending). A line whose detail record is gone (404) keeps its budgeted
  /// amount; any other failure (401, network, server error) fails the month,
  /// so a partial month is never cached as complete.
  Future<List<BudgetCategory>> _withDerivedAmounts(
    String accessToken,
    List<BudgetCategory> categories,
  ) async {
    final detailed = List<BudgetCategory>.of(categories);
    for (var i = 0; i < categories.length; i += _categoryConcurrency) {
      final end = (i + _categoryConcurrency).clamp(0, categories.length);
      final batch = await Future.wait([
        for (var j = i; j < end; j++)
          _service.getBudgetCategory(
            accessToken: accessToken,
            id: categories[j].id,
          ),
      ]);
      for (var k = 0; k < batch.length; k++) {
        final result = batch[k];
        if (result['success'] == true) {
          detailed[i + k] = result['budget_category'] as BudgetCategory;
        } else if (result['error'] != 'not_found') {
          _throwIfFailed(result);
        }
      }
    }
    return detailed;
  }

  void _throwIfFailed(Map<String, dynamic> result) {
    if (result['success'] == true) return;
    final error = result['error']?.toString();
    throw _BudgetsFetchException(
      error == 'unauthorized'
          ? BudgetsLoadError.unauthorized
          : BudgetsLoadError.failed,
      error == 'unauthorized' ? null : error,
    );
  }

  @override
  void notifyListeners() {
    // A month load can complete after the owning screen disposed this.
    if (!_isDisposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _generation++;
    super.dispose();
  }

  static DateTime _firstOfMonth(DateTime date) =>
      DateTime(date.year, date.month);

  static String _monthKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';

  static DateTime? _parseMonthKey(Object? value) {
    final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch('${value ?? ''}');
    if (match == null) return null;
    return DateTime(int.parse(match[1]!), int.parse(match[2]!));
  }
}

class _MonthData {
  const _MonthData({
    required this.budgets,
    this.selected,
    this.categories = const [],
  });

  final List<Budget> budgets;
  final Budget? selected;
  final List<BudgetCategory> categories;
}

class _BudgetsFetchException implements Exception {
  const _BudgetsFetchException(this.error, this.message);

  final BudgetsLoadError error;
  final String? message;

  @override
  String toString() => 'BudgetsFetchException($error, $message)';
}
