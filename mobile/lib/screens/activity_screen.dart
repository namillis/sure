import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../models/activity_filters.dart';
import '../models/activity_transaction.dart';
import '../models/offline_transaction.dart';
import '../providers/accounts_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/privacy_provider.dart';
import '../providers/tags_provider.dart';
import '../providers/transactions_provider.dart';
import '../services/transaction_search_service.dart';
import '../theme/sure_colors.dart';
import '../utils/activity_totals.dart';
import '../utils/money_masker.dart';
import '../widgets/activity_option_sheet.dart';
import '../widgets/budget_progress_bar.dart' show parseCategoryColor;
import '../widgets/ds/ds.dart';
import '../widgets/sure_button.dart';
import 'transaction_sheet.dart';
import 'transaction_form_screen.dart';

/// The Activity tab: every transaction across accounts, newest first, with
/// server-side search (`search` matches name, notes and merchant), date,
/// category, account, tag and type filters, a money in/out summary, day
/// sections, infinite scroll, swipe-to-categorize/delete and a multi-select
/// (long-press or the nav bar toggle) for bulk categorize and delete.
///
/// A tab root: it has its own [Scaffold] and never shows a back button.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, this.service, this.accessTokenLoader});

  /// Injected for tests.
  final TransactionSearchService? service;
  final Future<String?> Function()? accessTokenLoader;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

enum _BulkAction { categorize, delete }

class _ActivityScreenState extends State<ActivityScreen> {
  static const int _perPage = 50;
  static const Duration _searchDebounce = Duration(milliseconds: 350);

  /// Ids for the "All types" choice in the type picker.
  static const String _allTypesId = 'all';

  late final TransactionSearchService _service =
      widget.service ?? TransactionSearchService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;

  ActivityFilters _filters = const ActivityFilters();
  final List<ActivityTransaction> _rows = [];
  int _page = 0;
  int _totalPages = 1;
  int _totalCount = 0;
  bool _loading = false;
  bool _failed = false;

  /// Whether the request that failed was a reload from page one, so its retry
  /// repeats it instead of appending the next page to stale rows.
  bool _failedWasReset = false;

  /// Bumped on every reload so a response for an older query is dropped.
  int _generation = 0;

  bool _selectionMode = false;
  final Set<String> _selected = {};
  _BulkAction? _bulkAction;
  int _bulkDone = 0;
  int _bulkTotal = 0;

  bool get _hasMore => _page < _totalPages;
  bool get _bulkRunning => _bulkAction != null;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load(reset: true);
      _loadFilterOptions();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<String?> _accessToken() {
    final loader = widget.accessTokenLoader;
    if (loader != null) return loader();
    return context.read<AuthProvider>().getValidAccessToken();
  }

  Future<void> _logout() async {
    if (widget.accessTokenLoader != null) return; // Tests have no session.
    await context.read<AuthProvider>().logout();
  }

  Future<void> _loadFilterOptions() async {
    final categories = context.read<CategoriesProvider>();
    final tags = context.read<TagsProvider>();
    final accounts = context.read<AccountsProvider>();
    final token = await _accessToken();
    if (token == null || !mounted) return;
    try {
      await Future.wait([
        categories.fetchCategories(accessToken: token),
        tags.fetchTags(accessToken: token),
        if (accounts.accounts.isEmpty)
          accounts.fetchAccounts(accessToken: token),
      ]);
    } catch (_) {
      // Providers keep their own error state; the filter sheets show empty.
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    final generation = reset ? ++_generation : _generation;
    setState(() {
      _loading = true;
      _failed = false;
    });

    final token = await _accessToken();
    if (!mounted || generation != _generation) return;
    if (token == null) {
      setState(() {
        _loading = false;
        _failed = true;
        _failedWasReset = reset;
      });
      return;
    }

    final nextPage = reset ? 1 : _page + 1;
    final result = await _service.search(
      accessToken: token,
      filters: _filters,
      page: nextPage,
      perPage: _perPage,
    );
    if (!mounted || generation != _generation) return;

    if (result['error'] == 'unauthorized') {
      setState(() => _loading = false);
      await _logout();
      return;
    }

    setState(() {
      _loading = false;
      if (result['success'] == true) {
        if (reset) _rows.clear();
        _rows.addAll(result['transactions'] as List<ActivityTransaction>);
        _page = nextPage;
        _totalPages = result['totalPages'] as int;
        _totalCount = (result['totalCount'] as int?) ?? _rows.length;
      } else {
        _failed = true;
        _failedWasReset = reset;
      }
    });

    // A short first page may not fill the screen, so no scroll would ever
    // ask for the next one.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
  }

  void _maybeLoadMore() {
    if (!mounted || _loading || _failed || !_hasMore) return;
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 600) _load();
  }

  void _applyFilters(ActivityFilters filters) {
    setState(() => _filters = filters);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    _load(reset: true);
  }

  void _onSearchChanged(String value) {
    // The field's clear button reports ''; apply that at once.
    if (value.isEmpty) {
      _clearSearch();
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(_searchDebounce, () {
      if (!mounted || value.trim() == _filters.search.trim()) return;
      _applyFilters(_filters.copyWith(search: value));
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    if (_searchController.text.isNotEmpty) _searchController.clear();
    if (_filters.search.isEmpty) return;
    _applyFilters(_filters.copyWith(search: ''));
  }

  void _clearAll() {
    _debounce?.cancel();
    _searchController.clear();
    _applyFilters(const ActivityFilters());
  }

  // ---- Filters -------------------------------------------------------------

  String _presetLabel(AppLocalizations l, ActivityDatePreset preset) {
    switch (preset) {
      case ActivityDatePreset.thisMonth:
        return l.activityDateThisMonth;
      case ActivityDatePreset.lastMonth:
        return l.activityDateLastMonth;
      case ActivityDatePreset.last90Days:
        return l.activityDateLast90Days;
      case ActivityDatePreset.thisYear:
        return l.activityDateThisYear;
      case ActivityDatePreset.all:
        return l.activityDateAll;
      case ActivityDatePreset.custom:
        return l.activityDateCustom;
    }
  }

  String _dateChipLabel(AppLocalizations l) {
    final start = _filters.customStart;
    final end = _filters.customEnd;
    if (_filters.datePreset == ActivityDatePreset.custom &&
        start != null &&
        end != null) {
      return SureDates.rangeOf(context, start, end);
    }
    return _presetLabel(l, _filters.datePreset);
  }

  Future<void> _pickDate() async {
    final l = AppLocalizations.of(context);
    final id = await ActivityOptionSheet.pickOne(
      context,
      title: l.activityFilterDate,
      options: [
        for (final option in ActivityDatePreset.values)
          ActivityOption(id: option.name, label: _presetLabel(l, option)),
      ],
      selected: _filters.datePreset.name,
    );
    if (id == null || !mounted) return;
    final preset = ActivityDatePreset.values.byName(id);

    if (preset != ActivityDatePreset.custom) {
      _applyFilters(_filters.copyWith(datePreset: preset));
      return;
    }

    final now = DateTime.now();
    final current = _filters.dateRange(now);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1970),
      lastDate: DateTime(now.year + 5, 12, 31),
      initialDateRange: current.start != null && current.end != null
          ? DateTimeRange(start: current.start!, end: current.end!)
          : null,
    );
    if (range == null || !mounted) return;
    _applyFilters(
      _filters.copyWith(
        datePreset: ActivityDatePreset.custom,
        customStart: range.start,
        customEnd: range.end,
      ),
    );
  }

  List<ActivityOption> _categoryOptions() {
    final categories = [...context.read<CategoriesProvider>().categories]
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    return [
      for (final category in categories)
        ActivityOption(
          id: category.id,
          label: category.displayName,
          color: parseCategoryColor(category.color),
        ),
    ];
  }

  Future<void> _pickCategories() async {
    final ids = await ActivityOptionSheet.pickMany(
      context,
      title: AppLocalizations.of(context).activityFilterCategory,
      options: _categoryOptions(),
      selected: _filters.categoryIds,
    );
    if (ids != null && mounted) {
      _applyFilters(_filters.copyWith(categoryIds: ids));
    }
  }

  Future<void> _pickAccounts() async {
    final accounts = context.read<AccountsProvider>().accounts;
    final ids = await ActivityOptionSheet.pickMany(
      context,
      title: AppLocalizations.of(context).activityFilterAccount,
      options: [
        for (final account in accounts)
          ActivityOption(id: account.id, label: account.name),
      ],
      selected: _filters.accountIds,
    );
    if (ids != null && mounted) {
      _applyFilters(_filters.copyWith(accountIds: ids));
    }
  }

  Future<void> _pickTags() async {
    final tags = context.read<TagsProvider>().tags;
    final ids = await ActivityOptionSheet.pickMany(
      context,
      title: AppLocalizations.of(context).activityFilterTags,
      options: [
        for (final tag in tags)
          ActivityOption(
            id: tag.id,
            label: tag.name,
            color: parseCategoryColor(tag.color),
          ),
      ],
      selected: _filters.tagIds,
    );
    if (ids != null && mounted) {
      _applyFilters(_filters.copyWith(tagIds: ids));
    }
  }

  String _typeLabel(AppLocalizations l, ActivityTypeFilter? type) {
    switch (type) {
      case null:
        return l.activityTypeAll;
      case ActivityTypeFilter.expense:
        return l.activityTypeExpense;
      case ActivityTypeFilter.income:
        return l.activityTypeIncome;
    }
  }

  Future<void> _pickType() async {
    final l = AppLocalizations.of(context);
    final id = await ActivityOptionSheet.pickOne(
      context,
      title: l.activityFilterType,
      options: [
        ActivityOption(id: _allTypesId, label: _typeLabel(l, null)),
        for (final option in ActivityTypeFilter.values)
          ActivityOption(id: option.name, label: _typeLabel(l, option)),
      ],
      selected: _filters.type?.name ?? _allTypesId,
    );
    if (id == null || !mounted) return;
    _applyFilters(
      _filters.copyWith(
        type: id == _allTypesId ? null : ActivityTypeFilter.values.byName(id),
      ),
    );
  }

  // ---- Row actions ---------------------------------------------------------

  Future<void> _openEdit(ActivityTransaction row) async {
    final updated = await showTransactionSheet(
      context,
      transaction: OfflineTransaction.fromTransaction(
        row.transaction,
        localId: row.id ?? '',
      ),
    );
    if (updated == true && mounted) await _load(reset: true);
  }

  void _enterSelection() {
    setState(() => _selectionMode = true);
  }

  void _startSelection(ActivityTransaction row) {
    if (row.id == null) return;
    setState(() {
      _selectionMode = true;
      _selected.add(row.id!);
    });
  }

  void _toggleSelected(ActivityTransaction row) {
    final id = row.id;
    if (id == null || _bulkRunning) return;
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _exitSelection() {
    if (_bulkRunning) return;
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  void _showSnack(String message, {bool error = false}) {
    final palette = SureColors.of(context).palette;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? palette.destructive : null,
      ),
    );
  }

  /// Shows the outcome of a bulk action. Failed ids stay selected so the user
  /// can retry them; a clean run leaves selection mode.
  void _finishBulk(Set<String> failed, int total, String allDoneMessage) {
    final l = AppLocalizations.of(context);
    setState(() {
      _bulkAction = null;
      _selected
        ..clear()
        ..addAll(failed);
      if (failed.isEmpty) _selectionMode = false;
    });
    if (failed.isEmpty) {
      _showSnack(allDoneMessage);
    } else {
      _showSnack(
        l.activityBulkPartial(total - failed.length, total, failed.length),
        error: true,
      );
    }
  }

  Future<void> _categorizeSelected() => _categorize(_selected.toList());

  /// Categorizes [ids] one by one. From selection mode ([bulk]) it shows
  /// progress and keeps failed rows selected; a single row from its swipe
  /// action just reports the result.
  Future<void> _categorize(List<String> ids, {bool bulk = true}) async {
    final l = AppLocalizations.of(context);
    if (ids.isEmpty) return;

    final categoryId = await ActivityOptionSheet.pickOne(
      context,
      title: l.activityPickCategory,
      options: _categoryOptions(),
    );
    if (categoryId == null || !mounted) return;
    final category = context
        .read<CategoriesProvider>()
        .categories
        .where((c) => c.id == categoryId)
        .firstOrNull;

    final token = await _accessToken();
    if (!mounted) return;
    if (token == null) {
      _showSnack(l.activitySessionExpired, error: true);
      return;
    }

    if (bulk) {
      setState(() {
        _bulkAction = _BulkAction.categorize;
        _bulkDone = 0;
        _bulkTotal = ids.length;
      });
    }

    final failed = <String>{};
    for (final id in ids) {
      final result = await _service.updateCategory(
        accessToken: token,
        transactionId: id,
        categoryId: categoryId,
      );
      if (!mounted) return;
      if (result['error'] == 'unauthorized') {
        setState(() => _bulkAction = null);
        await _logout();
        return;
      }
      setState(() {
        if (bulk) _bulkDone++;
        if (result['success'] != true) {
          failed.add(id);
          return;
        }
        final index = _rows.indexWhere((row) => row.id == id);
        if (index < 0) return;
        final updated = result['transaction'];
        _rows[index] = updated is ActivityTransaction
            ? updated
            : _rows[index].withCategory(
                id: categoryId,
                name: category?.displayName ?? '',
                color: category?.color,
                icon: category?.icon,
              );
      });
    }

    if (bulk) {
      _finishBulk(failed, ids.length, l.activityCategorized(ids.length));
    } else if (failed.isEmpty) {
      _showSnack(l.activityCategorized(ids.length));
    } else {
      _showSnack(l.dsaCategorizeFailed, error: true);
    }
    // Recategorized rows may no longer match a category filter.
    if (failed.length < ids.length && _filters.categoryIds.isNotEmpty) {
      await _load(reset: true);
    }
  }

  Future<bool> _confirmDelete({ActivityTransaction? single}) async {
    final palette = SureColors.of(context).palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final dl = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(single == null
              ? dl.transactionsListDeleteMultiTitle
              : dl.transactionsListDeleteTitle),
          content: Text(single == null
              ? dl.transactionsListDeleteMultiContent
              : dl.transactionsListDeleteSingleContent(
                  single.transaction.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(dl.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: palette.destructive,
              ),
              child: Text(dl.commonDelete),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  /// Deletes one row from its swipe action, after the usual confirm.
  Future<void> _deleteOne(ActivityTransaction row) async {
    final l = AppLocalizations.of(context);
    final id = row.id;
    if (id == null) return;
    if (!await _confirmDelete(single: row) || !mounted) return;

    final transactions = context.read<TransactionsProvider>();
    final token = await _accessToken();
    if (!mounted) return;
    if (token == null) {
      _showSnack(l.activitySessionExpired, error: true);
      return;
    }
    final ok = await transactions.deleteTransaction(
      accessToken: token,
      transactionId: id,
    );
    if (!mounted) return;
    if (ok) {
      setState(() => _rows.removeWhere((r) => r.id == id));
      _showSnack(l.transactionsListDeletedSuccess);
    } else {
      _showSnack(l.transactionsListDeleteFailed, error: true);
    }
  }

  Future<void> _deleteSelected() async {
    final l = AppLocalizations.of(context);
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    if (!await _confirmDelete() || !mounted) return;

    final transactions = context.read<TransactionsProvider>();
    final token = await _accessToken();
    if (!mounted) return;
    if (token == null) {
      _showSnack(l.activitySessionExpired, error: true);
      return;
    }

    setState(() {
      _bulkAction = _BulkAction.delete;
      _bulkDone = 0;
      _bulkTotal = ids.length;
    });

    // One at a time through the app's delete flow, so each failure is known
    // and offline deletes are queued the same way as elsewhere.
    final failed = <String>{};
    for (final id in ids) {
      final ok = await transactions.deleteTransaction(
        accessToken: token,
        transactionId: id,
      );
      if (!mounted) return;
      setState(() {
        _bulkDone++;
        if (ok) {
          _rows.removeWhere((row) => row.id == id);
        } else {
          failed.add(id);
        }
      });
    }

    _finishBulk(failed, ids.length, l.transactionsListDeletedMulti(ids.length));
  }

  Future<void> _addTransaction() async {
    final l = AppLocalizations.of(context);
    final accountsProvider = context.read<AccountsProvider>();
    if (accountsProvider.accounts.isEmpty) {
      final token = await _accessToken();
      if (token != null) {
        await accountsProvider.fetchAccounts(accessToken: token);
      }
      if (!mounted) return;
    }
    final accounts = accountsProvider.accounts;
    if (accounts.isEmpty) {
      _showSnack(l.activityNoAccounts);
      return;
    }

    Account? account = accounts.length == 1 ? accounts.first : null;
    if (account == null) {
      final id = await ActivityOptionSheet.pickOne(
        context,
        title: l.activityPickAccount,
        options: [
          for (final a in accounts) ActivityOption(id: a.id, label: a.name),
        ],
      );
      if (id == null || !mounted) return;
      account = accounts.firstWhere((a) => a.id == id);
    }

    final created = await showTransactionFormSheet(context, account: account);
    if (created == true && mounted) await _load(reset: true);
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitSelection();
      },
      child: Scaffold(
        backgroundColor: palette.surface,
        body: RefreshIndicator(
          onRefresh: () => _load(reset: true),
          edgeOffset: MediaQuery.paddingOf(context).top +
              SureLargeTitleHeader.barHeight,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SureLargeTitleHeader(
                title: _selectionMode
                    ? l.activitySelectedCount(_selected.length)
                    : l.activity,
                automaticallyImplyLeading: false,
                actions: _headerActions(l),
              ),
              SliverToBoxAdapter(child: _buildControls(l)),
              ..._buildResults(l),
              // Keep the last row clear of the tab bar (and the home
              // indicator) when the shell draws the bar over content.
              SliverPadding(
                padding: EdgeInsets.only(
                  bottom: 24 + MediaQuery.paddingOf(context).bottom,
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _selectionMode ? _buildSelectionBar(l) : null,
      ),
    );
  }

  List<Widget> _headerActions(AppLocalizations l) {
    if (_selectionMode) {
      return [
        SureNavTextButton(
          label: l.commonCancel,
          onPressed: _bulkRunning ? null : _exitSelection,
        ),
      ];
    }
    return [
      SureNavIconButton(
        icon: SureIcons.listChecks,
        semanticLabel: l.dsaSelect,
        onPressed: _rows.isEmpty ? null : _enterSelection,
      ),
      SureNavIconButton(
        icon: SureIcons.plus,
        semanticLabel: l.activityAdd,
        onPressed: _addTransaction,
      ),
      const SizedBox(width: 4),
    ];
  }

  Widget _buildControls(AppLocalizations l) {
    final summary = _buildSummary(l);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: SureSearchField(
            controller: _searchController,
            hintText: l.activitySearchHint,
            clearSemanticLabel: l.activityClearSearch,
            onChanged: _onSearchChanged,
          ),
        ),
        _buildFilterRow(l),
        if (summary != null) summary,
      ],
    );
  }

  Widget _buildFilterRow(AppLocalizations l) {
    final palette = SureColors.of(context).palette;
    String counted(String label, int count) =>
        count == 0 ? label : l.activityFilterCount(label, count);

    final chips = <Widget>[
      SureChip(
        label: _dateChipLabel(l),
        selected: true,
        dropdown: true,
        onSelected: (_) => _pickDate(),
      ),
      SureChip(
        label: counted(l.activityFilterCategory, _filters.categoryIds.length),
        selected: _filters.categoryIds.isNotEmpty,
        dropdown: true,
        onSelected: (_) => _pickCategories(),
      ),
      SureChip(
        label: counted(l.activityFilterAccount, _filters.accountIds.length),
        selected: _filters.accountIds.isNotEmpty,
        dropdown: true,
        onSelected: (_) => _pickAccounts(),
      ),
      SureChip(
        label: counted(l.activityFilterTags, _filters.tagIds.length),
        selected: _filters.tagIds.isNotEmpty,
        dropdown: true,
        onSelected: (_) => _pickTags(),
      ),
      SureChip(
        label: _filters.type == null
            ? l.activityFilterType
            : _typeLabel(l, _filters.type),
        selected: _filters.type != null,
        dropdown: true,
        onSelected: (_) => _pickType(),
      ),
      if (_filters.hasActiveFilters)
        TextButton(
          onPressed: _clearAll,
          style: TextButton.styleFrom(foregroundColor: palette.link),
          child: Text(l.activityClearAll),
        ),
    ];

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) => Center(child: chips[index]),
      ),
    );
  }

  /// "Nov 1–11 · In $1,926.88 · Out $8,634.42". The API has no totals for a
  /// filter, so the sums cover the loaded rows; while more pages remain, a
  /// second line says how many of the matches that is.
  Widget? _buildSummary(AppLocalizations l) {
    if (_rows.isEmpty) return null;
    final palette = SureColors.of(context).palette;
    final hidden = context.watch<PrivacyProvider>().hidden;
    final locale = Localizations.localeOf(context).toString();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final range = _filters.dateRange(now);
    final start = range.start;
    var end = range.end;
    final String rangeLabel;
    if (start != null && end != null) {
      // "This month" on Nov 11 reads "Nov 1–11", not "Nov 1–30".
      if (end.isAfter(today) && !today.isBefore(start)) end = today;
      rangeLabel = SureDates.rangeOf(context, start, end);
    } else {
      rangeLabel = _presetLabel(l, _filters.datePreset);
    }

    final totals = ActivityTotals.of(_rows);
    String money(double value) => MoneyMasker.mask(
          ActivityTotals.format(value, totals?.currency, locale: locale),
          hidden: hidden,
        );
    // Mixed currencies have no meaningful sum: show the range alone.
    final line = totals == null || totals.currency == null
        ? rangeLabel
        : l.dsaSummary(rangeLabel, money(totals.inflow), money(totals.outflow));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MoneyText(
            line,
            trend: MoneyTrend.neutral,
            color: palette.textSecondary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          if (_hasMore)
            Text(
              l.dsaSummaryPartial(_rows.length, _totalCount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: palette.textSubdued),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildResults(AppLocalizations l) {
    if (_rows.isEmpty) return [_buildEmpty(l)];

    final locale = Localizations.localeOf(context).toString();
    final hideAmounts = context.watch<PrivacyProvider>().hidden;
    final accounts = {
      for (final a in context.watch<AccountsProvider>().accounts) a.id: a,
    };

    final slivers = <Widget>[];
    for (final group in ActivityTransaction.groupByDay(_rows)) {
      final day = group.day;
      final totals = ActivityTotals.of(group.rows);
      final total = totals == null || totals.currency == null
          ? null
          : MoneyMasker.mask(totals.formatNet(locale: locale),
              hidden: hideAmounts);
      slivers.add(
        SliverMainAxisGroup(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _DayHeaderDelegate(
                label: day == null
                    ? l.activityUnknownDate
                    : SureDates.relativeDayOf(context, day),
                total: total,
              ),
            ),
            SliverToBoxAdapter(
              child: SurePanel.rows(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                dividerIndent: SurePanel.iconRowDividerIndent,
                children: [
                  for (final row in group.rows)
                    _row(row, accounts[row.transaction.accountId], hideAmounts),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_hasMore || _failed) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _failed
                  ? SureButton(
                      label: l.commonTryAgain,
                      onPressed: () => _load(reset: _failedWasReset),
                      variant: SureButtonVariant.outline,
                      size: SureButtonSize.sm,
                    )
                  : _loading
                      ? const CircularProgressIndicator()
                      : const SizedBox(height: 36),
            ),
          ),
        ),
      );
    }
    return slivers;
  }

  Widget _row(ActivityTransaction row, Account? account, bool hideAmounts) {
    final actionable = row.id != null && !_selectionMode && !_bulkRunning;
    return SureTransactionRow.activity(
      row,
      account: account,
      hideAmount: hideAmounts,
      selectionMode: _selectionMode,
      selected: _selected.contains(row.id),
      onTap: () => _selectionMode ? _toggleSelected(row) : _openEdit(row),
      onLongPress: () =>
          _selectionMode ? _toggleSelected(row) : _startSelection(row),
      onCategorize:
          actionable ? () => _categorize([row.id!], bulk: false) : null,
      onDelete: actionable ? () => _deleteOne(row) : null,
    );
  }

  Widget _buildEmpty(AppLocalizations l) {
    final Widget content;
    if (_loading) {
      content = const CircularProgressIndicator();
    } else if (_failed) {
      content = SureEmptyState(
        icon: SureIcons.circleAlert,
        title: l.activityLoadFailed,
        primaryLabel: l.commonTryAgain,
        onPrimary: () => _load(reset: true),
      );
    } else if (_hasNonDateFilters ||
        (_filters.datePreset != ActivityDatePreset.thisMonth &&
            _filters.datePreset != ActivityDatePreset.all)) {
      final term = _filters.search.trim();
      content = SureEmptyState(
        icon: SureIcons.search,
        title: term.isEmpty ? l.dsaNoMatches : l.dsaNoMatchesFor(term),
        body: l.dsaNoMatchesBody,
        secondaryLabel: l.activityClearFilters,
        onSecondary: _clearAll,
      );
    } else if (_filters.datePreset == ActivityDatePreset.all) {
      // Nothing filtered and nothing ever: no transactions at all.
      content = SureEmptyState(
        icon: SureIcons.receipt,
        title: l.dsaEmptyTitle,
        body: l.dsaEmptyBody,
      );
    } else {
      content = SureEmptyState(
        icon: SureIcons.receipt,
        title: l.activityEmpty,
        body: l.dsaEmptyMonthBody,
      );
    }
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 48),
        child: Center(child: content),
      ),
    );
  }

  /// Any filter besides the date range (search included).
  bool get _hasNonDateFilters =>
      _filters.search.trim().isNotEmpty ||
      _filters.categoryIds.isNotEmpty ||
      _filters.accountIds.isNotEmpty ||
      _filters.tagIds.isNotEmpty ||
      _filters.type != null;

  Widget _buildSelectionBar(AppLocalizations l) {
    final colors = SureColors.of(context);
    final palette = colors.palette;
    final Widget content;
    if (_bulkRunning) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _bulkAction == _BulkAction.categorize
                ? l.activityCategorizing(_bulkDone, _bulkTotal)
                : l.activityDeleting(_bulkDone, _bulkTotal),
            style: TextStyle(fontSize: 14, color: palette.textPrimary),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _bulkTotal == 0 ? null : _bulkDone / _bulkTotal,
          ),
        ],
      );
    } else {
      final enabled = _selected.isNotEmpty;
      // SureButton centers itself in the height it is given, and the bottom
      // bar slot offers the whole screen, so pin the row to the lg height.
      content = SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(
              child: SureButton(
                label: l.activityCategorize,
                leading: const SureIcon(SureIcons.tag, size: 18),
                onPressed: enabled ? _categorizeSelected : null,
                variant: SureButtonVariant.outline,
                size: SureButtonSize.lg,
                fullWidth: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SureButton(
                label: l.commonDelete,
                leading: const SureIcon(SureIcons.trash, size: 18),
                onPressed: enabled ? _deleteSelected : null,
                variant: SureButtonVariant.destructive,
                size: SureButtonSize.lg,
                fullWidth: true,
              ),
            ),
          ],
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.container,
        border: Border(top: BorderSide(color: colors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: content,
        ),
      ),
    );
  }
}

class _DayHeaderDelegate extends SliverPersistentHeaderDelegate {
  _DayHeaderDelegate({required this.label, required this.total});

  final String label;
  final String? total;

  @override
  double get minExtent => SureDayHeader.height;

  @override
  double get maxExtent => SureDayHeader.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) =>
      SureDayHeader(label: label, total: total);

  @override
  bool shouldRebuild(_DayHeaderDelegate oldDelegate) =>
      label != oldDelegate.label || total != oldDelegate.total;
}
