import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
import '../theme/sure_spacing.dart';
import '../theme/sure_tokens.dart';
import '../utils/money_masker.dart';
import '../utils/transaction_amount_display.dart';
import '../widgets/activity_option_sheet.dart';
import '../widgets/budget_progress_bar.dart' show parseCategoryColor;
import '../widgets/money_text.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_chip.dart';
import '../widgets/sure_text_field.dart';
import 'transaction_edit_screen.dart';
import 'transaction_form_screen.dart';

/// The Activity tab: every transaction across accounts, newest first, with
/// server-side search (`search` matches name, notes and merchant), date,
/// category, account, tag and type filters, day headers, infinite scroll and
/// a long-press multi-select for bulk categorize and delete.
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

  late final TransactionSearchService _service =
      widget.service ?? TransactionSearchService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;

  ActivityFilters _filters = const ActivityFilters();
  final List<ActivityTransaction> _rows = [];
  int _page = 0;
  int _totalPages = 1;
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
    setState(() {}); // Show or hide the clear button.
    _debounce?.cancel();
    _debounce = Timer(_searchDebounce, () {
      if (!mounted || value.trim() == _filters.search.trim()) return;
      _applyFilters(_filters.copyWith(search: value));
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    if (_filters.search.isEmpty) {
      setState(() {});
      return;
    }
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

  String _dateChipLabel(AppLocalizations l, String locale) {
    final start = _filters.customStart;
    final end = _filters.customEnd;
    if (_filters.datePreset == ActivityDatePreset.custom &&
        start != null &&
        end != null) {
      final format = start.year == end.year
          ? DateFormat.MMMd(locale)
          : DateFormat.yMMMd(locale);
      return l.activityDateRange(format.format(start), format.format(end));
    }
    return _presetLabel(l, _filters.datePreset);
  }

  Future<void> _pickDate() async {
    final l = AppLocalizations.of(context);
    final preset = await showModalBottomSheet<ActivityDatePreset>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetTitle(l.activityFilterDate),
            for (final option in ActivityDatePreset.values)
              ListTile(
                minTileHeight: 48,
                title: Text(_presetLabel(l, option)),
                trailing: option == _filters.datePreset
                    ? const Icon(Icons.check)
                    : null,
                selected: option == _filters.datePreset,
                onTap: () => Navigator.pop(context, option),
              ),
          ],
        ),
      ),
    );
    if (preset == null || !mounted) return;

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
    // Wrapped so "All types" (null) is distinguishable from a dismissal.
    final picked = await showModalBottomSheet<List<ActivityTypeFilter?>>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetTitle(l.activityFilterType),
            for (final option in <ActivityTypeFilter?>[
              null,
              ...ActivityTypeFilter.values,
            ])
              ListTile(
                minTileHeight: 48,
                title: Text(_typeLabel(l, option)),
                trailing:
                    option == _filters.type ? const Icon(Icons.check) : null,
                selected: option == _filters.type,
                onTap: () => Navigator.pop(context, [option]),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _applyFilters(_filters.copyWith(type: picked.first));
  }

  // ---- Row actions ---------------------------------------------------------

  Future<void> _openEdit(ActivityTransaction row) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => TransactionEditScreen(
          transaction: OfflineTransaction.fromTransaction(
            row.transaction,
            localId: row.id ?? '',
          ),
        ),
      ),
    );
    if (updated == true && mounted) await _load(reset: true);
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

  Future<void> _categorizeSelected() async {
    final l = AppLocalizations.of(context);
    final ids = _selected.toList();
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

    setState(() {
      _bulkAction = _BulkAction.categorize;
      _bulkDone = 0;
      _bulkTotal = ids.length;
    });

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
        _bulkDone++;
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
              );
      });
    }

    _finishBulk(failed, ids.length, l.activityCategorized(ids.length));
    // Recategorized rows may no longer match a category filter.
    if (failed.length < ids.length && _filters.categoryIds.isNotEmpty) {
      await _load(reset: true);
    }
  }

  Future<void> _deleteSelected() async {
    final l = AppLocalizations.of(context);
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final palette = SureColors.of(context).palette;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final dl = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(dl.transactionsListDeleteMultiTitle),
          content: Text(dl.transactionsListDeleteMultiContent),
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
    if (confirmed != true || !mounted) return;

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

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TransactionFormScreen(account: account!),
    );
    if (created == true && mounted) await _load(reset: true);
  }

  // ---- Build ---------------------------------------------------------------

  String _dayLabel(AppLocalizations l, DateTime? day, String locale) {
    if (day == null) return l.activityUnknownDate;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final difference = today.difference(day).inDays;
    if (difference == 0) return l.activityToday;
    if (difference == 1) return l.activityYesterday;
    return day.year == today.year
        ? DateFormat.MMMEd(locale).format(day)
        : DateFormat.yMMMEd(locale).format(day);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitSelection();
      },
      child: Scaffold(
        appBar: _selectionMode
            ? AppBar(
                automaticallyImplyLeading: false,
                title: Text(l.activitySelectedCount(_selected.length)),
                actions: [
                  TextButton(
                    onPressed: _bulkRunning ? null : _exitSelection,
                    child: Text(l.commonCancel),
                  ),
                ],
              )
            : AppBar(
                automaticallyImplyLeading: false,
                title: Text(l.activity),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: l.activityAdd,
                    onPressed: _addTransaction,
                  ),
                ],
              ),
        body: Column(
          children: [
            _buildSearchField(l),
            _buildFilterRow(l),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _load(reset: true),
                child: _buildResults(l),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _selectionMode ? _buildSelectionBar(l) : null,
      ),
    );
  }

  Widget _buildSearchField(AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SureSpacing.xl,
        SureSpacing.md,
        SureSpacing.xl,
        SureSpacing.xs,
      ),
      child: SureTextField(
        controller: _searchController,
        hint: l.activitySearchHint,
        prefixIcon: const Icon(Icons.search),
        textInputAction: TextInputAction.search,
        onChanged: _onSearchChanged,
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                tooltip: l.activityClearSearch,
                onPressed: _clearSearch,
              ),
      ),
    );
  }

  Widget _buildFilterRow(AppLocalizations l) {
    final locale = Localizations.localeOf(context).toString();
    String counted(String label, int count) =>
        count == 0 ? label : l.activityFilterCount(label, count);

    final chips = <Widget>[
      SureChip(
        label: _dateChipLabel(l, locale),
        selected: _filters.datePreset != ActivityDatePreset.thisMonth,
        leading: const Icon(Icons.calendar_today_outlined, size: 16),
        onSelected: (_) => _pickDate(),
      ),
      SureChip(
        label: counted(l.activityFilterCategory, _filters.categoryIds.length),
        selected: _filters.categoryIds.isNotEmpty,
        onSelected: (_) => _pickCategories(),
      ),
      SureChip(
        label: counted(l.activityFilterAccount, _filters.accountIds.length),
        selected: _filters.accountIds.isNotEmpty,
        onSelected: (_) => _pickAccounts(),
      ),
      SureChip(
        label: counted(l.activityFilterTags, _filters.tagIds.length),
        selected: _filters.tagIds.isNotEmpty,
        onSelected: (_) => _pickTags(),
      ),
      SureChip(
        label: _filters.type == null
            ? l.activityFilterType
            : _typeLabel(l, _filters.type),
        selected: _filters.type != null,
        onSelected: (_) => _pickType(),
      ),
      if (_filters.hasActiveFilters)
        TextButton.icon(
          onPressed: _clearAll,
          icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
          label: Text(l.activityClearAll),
        ),
    ];

    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: SureSpacing.xl,
          vertical: SureSpacing.md,
        ),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: SureSpacing.md),
        itemBuilder: (_, index) => Center(child: chips[index]),
      ),
    );
  }

  Widget _buildResults(AppLocalizations l) {
    final locale = Localizations.localeOf(context).toString();
    final hideAmounts = context.watch<PrivacyProvider>().hidden;
    final accounts = {
      for (final a in context.watch<AccountsProvider>().accounts) a.id: a,
    };

    final slivers = <Widget>[];
    if (_rows.isEmpty) {
      if (_loading) {
        slivers.add(
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          ),
        );
      } else if (_failed) {
        slivers.add(
          _messageSliver(
            Icons.error_outline,
            l.activityLoadFailed,
            action: SureButton(
              label: l.commonTryAgain,
              onPressed: () => _load(reset: true),
              variant: SureButtonVariant.outline,
              size: SureButtonSize.sm,
            ),
          ),
        );
      } else if (_filters.hasActiveFilters) {
        slivers.add(
          _messageSliver(
            Icons.search_off,
            l.activityEmptyFiltered,
            action: SureButton(
              label: l.activityClearFilters,
              onPressed: _clearAll,
              variant: SureButtonVariant.outline,
              size: SureButtonSize.sm,
            ),
          ),
        );
      } else {
        slivers.add(
          _messageSliver(Icons.receipt_long_outlined, l.activityEmpty),
        );
      }
    } else {
      for (final group in ActivityTransaction.groupByDay(_rows)) {
        slivers.add(
          SliverMainAxisGroup(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _DayHeaderDelegate(
                  _dayLabel(l, group.day, locale),
                  SureColors.of(context).palette,
                ),
              ),
              SliverList.builder(
                itemCount: group.rows.length,
                itemBuilder: (context, index) {
                  final row = group.rows[index];
                  final account = accounts[row.transaction.accountId];
                  return _ActivityRow(
                    row: row,
                    account: account,
                    hideAmounts: hideAmounts,
                    selectionMode: _selectionMode,
                    selected: _selected.contains(row.id),
                    onTap: () =>
                        _selectionMode ? _toggleSelected(row) : _openEdit(row),
                    onLongPress: () => _selectionMode
                        ? _toggleSelected(row)
                        : _startSelection(row),
                  );
                },
              ),
            ],
          ),
        );
      }
      if (_hasMore || _failed) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(SureSpacing.xl),
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
    }

    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: slivers,
    );
  }

  Widget _messageSliver(IconData icon, String message, {Widget? action}) {
    final palette = SureColors.of(context).palette;
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.all(SureSpacing.xxxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: palette.textSubdued),
            const SizedBox(height: SureSpacing.xl),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: palette.textSecondary),
            ),
            if (action != null) ...[
              const SizedBox(height: SureSpacing.xl),
              action,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionBar(AppLocalizations l) {
    final palette = SureColors.of(context).palette;
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
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: SureSpacing.md),
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
                leading: const Icon(Icons.label_outline, size: 18),
                onPressed: enabled ? _categorizeSelected : null,
                variant: SureButtonVariant.outline,
                size: SureButtonSize.lg,
                fullWidth: true,
              ),
            ),
            const SizedBox(width: SureSpacing.lg),
            Expanded(
              child: SureButton(
                label: l.commonDelete,
                leading: const Icon(Icons.delete_outline, size: 18),
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

    return Material(
      color: palette.container,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(SureSpacing.xl),
          child: content,
        ),
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SureSpacing.xl,
        SureSpacing.xl,
        SureSpacing.xl,
        SureSpacing.md,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: SureTokens.weightSemibold,
            ),
      ),
    );
  }
}

class _DayHeaderDelegate extends SliverPersistentHeaderDelegate {
  _DayHeaderDelegate(this.label, this.palette);

  final String label;
  final SureTokenPalette palette;

  static const double _height = 36;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Semantics(
      header: true,
      child: Container(
        height: _height,
        color: palette.surface,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: SureSpacing.xl),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: palette.textSecondary,
                fontWeight: SureTokens.weightSemibold,
              ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_DayHeaderDelegate oldDelegate) =>
      label != oldDelegate.label || palette != oldDelegate.palette;
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.row,
    required this.account,
    required this.hideAmounts,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final ActivityTransaction row;

  /// The row's account from [AccountsProvider], when it is loaded.
  final Account? account;
  final bool hideAmounts;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final textTheme = Theme.of(context).textTheme;
    final transaction = row.transaction;

    final type = row.accountType;
    final display = TransactionAmountDisplay.of(
      transaction.amount,
      isAsset: account?.isAsset ??
          TransactionAmountDisplay.assetAccountTypes.contains(type),
      isLiability: account?.isLiability ??
          TransactionAmountDisplay.liabilityAccountTypes.contains(type),
    );
    final color = SureMoney.color(context, display.trend);

    final accountName = row.accountName ?? account?.name;
    final merchant = transaction.merchantName;
    final subtitle = [
      if (accountName != null && accountName.isNotEmpty) accountName,
      if (merchant != null &&
          merchant.isNotEmpty &&
          merchant != transaction.name)
        merchant,
      if (row.isTransfer && row.transferAccountName != null)
        '${l.activityTransfer} · ${row.transferAccountName}',
    ].join(' · ');

    final categoryName = transaction.categoryName;

    return Material(
      color: selected ? palette.containerInset : palette.container,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SureSpacing.xl,
              vertical: SureSpacing.md,
            ),
            child: Row(
              children: [
                if (selectionMode)
                  Padding(
                    padding: const EdgeInsets.only(right: SureSpacing.md),
                    child: Checkbox(
                      value: selected,
                      onChanged: (_) => onTap(),
                    ),
                  )
                else
                  Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.only(right: SureSpacing.lg),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(SureTokens.radiusLg),
                    ),
                    child: Icon(display.icon, color: color, size: 20),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              transaction.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyLarge?.copyWith(
                                fontWeight: SureTokens.weightMedium,
                              ),
                            ),
                          ),
                          if (row.isSplitParent)
                            _FlagIcon(Icons.call_split, l.activitySplit),
                          if (row.isTransfer)
                            _FlagIcon(Icons.swap_horiz, l.activityTransfer),
                        ],
                      ),
                      if (categoryName != null && categoryName.isNotEmpty) ...[
                        const SizedBox(height: SureSpacing.xs),
                        _CategoryChip(
                          name: categoryName,
                          color: parseCategoryColor(row.categoryColor),
                        ),
                      ],
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: SureSpacing.xs),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: SureSpacing.md),
                MoneyText(
                  MoneyMasker.mask(display.text, hidden: hideAmounts),
                  trend: display.trend,
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: SureTokens.weightMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FlagIcon extends StatelessWidget {
  const _FlagIcon(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: SureSpacing.xs),
      child: Tooltip(
        message: label,
        child: Icon(
          icon,
          size: 16,
          color: SureColors.of(context).palette.textSecondary,
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.name, this.color});

  final String name;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final dot = color ?? palette.textSubdued;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SureSpacing.md,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: dot.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: SureSpacing.xs),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: SureTokens.weightMedium,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
