import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../providers/accounts_provider.dart';
import '../providers/transactions_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/privacy_provider.dart';
import '../services/log_service.dart';
import '../theme/sure_colors.dart';
import '../utils/amount_parser.dart';
import '../l10n/app_localizations.dart';
import '../utils/money_masker.dart';
import '../widgets/ds/ds.dart';

/// One account's month as a grid of daily net changes. Tap a day to select
/// it, tap it again for that day's transactions in a sheet.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, this.now});

  /// Clock for the starting month and the "today" mark; defaults to
  /// [DateTime.now].
  final DateTime Function()? now;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final LogService _log = LogService.instance;
  Account? _selectedAccount;
  late DateTime _currentMonth = (widget.now ?? DateTime.now)();
  Map<String, double> _dailyChanges = {};
  bool _isLoading = false;
  String _accountType = 'asset'; // 'asset' or 'liability'
  DateTime? _selectedDate; // Track selected date for tap interaction
  List<Transaction> _transactions = []; // Store transactions for filtering
  bool _accountsChecked = false; // The first accounts fetch has finished

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  Future<void> _loadInitialData() async {
    final accountsProvider = context.read<AccountsProvider>();
    final authProvider = context.read<AuthProvider>();

    final accessToken = await authProvider.getValidAccessToken();

    if (accountsProvider.accounts.isEmpty && accessToken != null) {
      await accountsProvider.fetchAccounts(
        accessToken: accessToken,
        forceSync: false,
      );
    }
    if (!mounted) return;
    setState(() => _accountsChecked = true);

    if (accountsProvider.accounts.isNotEmpty) {
      // Select first account of the selected type
      final filteredAccounts = _getFilteredAccounts(accountsProvider.accounts);
      setState(() {
        _selectedAccount =
            filteredAccounts.isNotEmpty ? filteredAccounts.first : null;
      });
      if (_selectedAccount != null) {
        await _loadTransactionsForAccount();
      }
    }
  }

  List<Account> _getFilteredAccounts(List<Account> accounts) {
    if (_accountType == 'asset') {
      return accounts.where((a) => a.isAsset).toList();
    } else {
      return accounts.where((a) => a.isLiability).toList();
    }
  }

  Future<void> _loadTransactionsForAccount() async {
    if (_selectedAccount == null) return;

    setState(() {
      _isLoading = true;
    });

    final authProvider = context.read<AuthProvider>();
    final transactionsProvider = context.read<TransactionsProvider>();

    final accessToken = await authProvider.getValidAccessToken();

    if (accessToken != null) {
      await transactionsProvider.fetchTransactions(
        accessToken: accessToken,
        accountId: _selectedAccount!.id,
        forceSync: false,
      );

      final transactions = transactionsProvider.transactions;
      _log.info(
        'CalendarScreen',
        'Loaded ${transactions.length} transactions for selected account',
      );

      // Store transactions for date filtering
      _transactions = List.from(transactions);

      _calculateDailyChanges(transactions);
      _log.info('CalendarScreen',
          'Calculated ${_dailyChanges.length} days with changes');
    }
    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });
  }

  void _calculateDailyChanges(List<Transaction> transactions) {
    final changes = <String, double>{};

    _log.debug('CalendarScreen',
        'Starting to calculate daily changes for ${transactions.length} transactions');

    for (var transaction in transactions) {
      try {
        final date = DateTime.parse(transaction.date);
        final dateKey = DateFormat('yyyy-MM-dd').format(date);

        var amount = AmountParser.parse(transaction.amount).value;

        // For asset accounts, flip the sign to match accounting conventions
        // For liability accounts, also flip the sign
        if (_selectedAccount?.isAsset == true ||
            _selectedAccount?.isLiability == true) {
          amount = -amount;
        }

        changes[dateKey] = (changes[dateKey] ?? 0.0) + amount;
      } catch (e) {
        final sanitizedError = LogService.sanitize(e.toString());
        final errorSummary = sanitizedError.length > 120
            ? '${sanitizedError.substring(0, 120)}...'
            : sanitizedError;
        _log.error('CalendarScreen',
            'Failed to process transaction for calendar: $errorSummary');
      }
    }

    _log.info(
        'CalendarScreen', 'Final changes map has ${changes.length} entries');

    if (!mounted) return;
    setState(() {
      _dailyChanges = changes;
    });
  }

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
      _selectedDate = null; // Clear selection when changing month
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
      _selectedDate = null; // Clear selection when changing month
    });
  }

  void _selectAccountType(String type) {
    final accounts = context.read<AccountsProvider>().accounts;
    setState(() {
      _accountType = type;
      // Switch to first account of new type
      final filteredAccounts = _getFilteredAccounts(accounts);
      _selectedAccount =
          filteredAccounts.isNotEmpty ? filteredAccounts.first : null;
      _dailyChanges = {};
      _transactions = [];
      _selectedDate = null; // Clear selection when changing account type
    });
    if (_selectedAccount != null) {
      _loadTransactionsForAccount();
    }
  }

  void _selectAccount(Account account) {
    setState(() {
      _selectedAccount = account;
      _dailyChanges = {};
      _transactions = [];
      _selectedDate = null; // Clear selection when changing account
    });
    _loadTransactionsForAccount();
  }

  Future<void> _pickAccount(List<Account> accounts) async {
    final l = AppLocalizations.of(context);
    final picked = await showSureSheet<Account>(
      context: context,
      builder: (sheetContext) {
        final palette = SureColors.of(sheetContext).palette;
        return SureSheet(
          title: l.activityFilterAccount,
          child: SafeArea(
            top: false,
            child: SurePanel.rows(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                for (final account in accounts)
                  SureListRow(
                    key: ValueKey('calendarAccount-${account.id}'),
                    title: account.name,
                    trailing: account.id == _selectedAccount?.id
                        ? SureIcon(SureIcons.check,
                            size: 18, color: palette.link)
                        : null,
                    onTap: () => Navigator.pop(sheetContext, account),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted || picked.id == _selectedAccount?.id) {
      return;
    }
    _selectAccount(picked);
  }

  void _onDayCellTap(DateTime date) {
    if (_selectedDate != null &&
        _selectedDate!.year == date.year &&
        _selectedDate!.month == date.month &&
        _selectedDate!.day == date.day) {
      // Second tap on same date - show transactions sheet
      _showTransactionsSheet(date);
    } else {
      // First tap - select the date
      setState(() {
        _selectedDate = date;
      });
    }
  }

  List<Transaction> _getTransactionsForDate(DateTime date) {
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    return _transactions.where((transaction) {
      try {
        final transactionDate = DateTime.parse(transaction.date);
        final transactionDateKey =
            DateFormat('yyyy-MM-dd').format(transactionDate);
        return transactionDateKey == dateKey;
      } catch (e) {
        return false;
      }
    }).toList();
  }

  void _showTransactionsSheet(DateTime date) {
    final transactions = _getTransactionsForDate(date);
    final l = AppLocalizations.of(context);
    final account = _selectedAccount;
    showSureSheet<void>(
      context: context,
      builder: (sheetContext) => SureSheet(
        title: SureDates.fullOf(sheetContext, date),
        showCancel: false,
        actionLabel: l.dsDone,
        onAction: () => Navigator.pop(sheetContext),
        child: SafeArea(
          top: false,
          child: transactions.isEmpty
              ? SureEmptyState(
                  icon: SureIcons.calendar,
                  title: l.calendarNoTransactions,
                )
              : SurePanel.rows(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  dividerIndent: SurePanel.iconRowDividerIndent,
                  children: [
                    // The row reads PrivacyProvider itself, so amounts
                    // re-mask if privacy is toggled while the sheet is open.
                    for (final transaction in transactions)
                      SureTransactionRow(
                        transaction: transaction,
                        account: account,
                        showAccount: false,
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  double _getTotalForMonth() {
    double total = 0.0;
    final yearMonth = DateFormat('yyyy-MM').format(_currentMonth);

    _dailyChanges.forEach((date, change) {
      if (date.startsWith(yearMonth)) {
        total += change;
      }
    });

    return total;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final accountsProvider = context.watch<AccountsProvider>();
    final hideAmounts = context.watch<PrivacyProvider>().hidden;
    final locale = Localizations.localeOf(context).toString();
    final accounts = _getFilteredAccounts(accountsProvider.accounts);
    final total = _getTotalForMonth();

    final Widget body;
    if (accounts.isEmpty && (!_accountsChecked || accountsProvider.isLoading)) {
      body = const Padding(
        padding: EdgeInsets.only(top: 96),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (accounts.isEmpty) {
      body = SureEmptyState(
        icon: SureIcons.wallet,
        title: l.ds4tCalendarNoAccounts,
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SurePanel.rows(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            children: [
              SureListRow(
                key: const ValueKey('calendarAccountRow'),
                title: l.activityFilterAccount,
                value: _selectedAccount?.name,
                showChevron: true,
                enabled: accounts.isNotEmpty,
                onTap: () => _pickAccount(accounts),
              ),
              SureListRow(
                title: l.ds4tCalendarMonthlyChange,
                trailing: MoneyText(
                  MoneyMasker.mask(
                    _formatTotal(total, locale),
                    hidden: hideAmounts,
                  ),
                  key: const ValueKey('calendarMonthTotal'),
                  trend: SureMoney.trendForAmount(total),
                  maxLines: 1,
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
          SurePanel(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SureNavIconButton(
                      icon: SureIcons.chevronLeft,
                      semanticLabel: l.budgetsPreviousMonth,
                      color: palette.link,
                      onPressed: _previousMonth,
                    ),
                    Expanded(
                      child: Text(
                        DateFormat.yMMMM(locale).format(_currentMonth),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    SureNavIconButton(
                      icon: SureIcons.chevronRight,
                      semanticLabel: l.budgetsNextMonth,
                      color: palette.link,
                      onPressed: _nextMonth,
                    ),
                  ],
                ),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 96),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  _buildCalendar(hideAmounts),
              ],
            ),
          ),
        ],
      );
    }

    return SureLargeTitleScaffold(
      title: l.calendarTitle,
      // The calendar opens from Settings' Tools group.
      leading: Navigator.of(context).canPop()
          ? SureBackButton(label: l.shellSettingsTitle)
          : null,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: SureSegmentedControl<String>(
              key: const ValueKey('calendarAccountType'),
              segments: [
                SureSegment(value: 'asset', label: l.calendarSegmentAssets),
                SureSegment(
                    value: 'liability', label: l.calendarSegmentLiabilities),
              ],
              selected: _accountType,
              onChanged: _selectAccountType,
            ),
          ),
        ),
        SliverToBoxAdapter(child: body),
      ],
    );
  }

  Widget _buildCalendar(bool hideAmounts) {
    final palette = SureColors.of(context).palette;
    final firstDayOfMonth =
        DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDayOfMonth =
        DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    final daysInMonth = lastDayOfMonth.day;
    final startWeekday = firstDayOfMonth.weekday % 7; // 0 = Sunday

    // Localized narrow weekday labels, Sunday→Saturday to match the
    // Sunday-anchored grid math above. 2024-01-07 is a Sunday, so indices
    // 0..6 map Sunday..Saturday.
    final localeName = Localizations.localeOf(context).toString();
    final weekdayLabels = List.generate(
      7,
      (i) => DateFormat.E(localeName)
          .format(DateTime(2024, 1, 7 + i))
          .substring(0, 1),
    );

    return Column(
      children: [
        // Weekday headers
        SizedBox(
          height: 28,
          child: Row(
            children: weekdayLabels.map((day) {
              return Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: palette.textSubdued,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // Calendar grid
        ...List.generate((daysInMonth + startWeekday + 6) ~/ 7, (weekIndex) {
          return SizedBox(
            height: 56,
            child: Row(
              children: List.generate(7, (dayIndex) {
                final dayNumber = weekIndex * 7 + dayIndex - startWeekday + 1;

                if (dayNumber < 1 || dayNumber > daysInMonth) {
                  return const Expanded(child: SizedBox.shrink());
                }

                final date =
                    DateTime(_currentMonth.year, _currentMonth.month, dayNumber);
                final dateKey = DateFormat('yyyy-MM-dd').format(date);
                final change = _dailyChanges[dateKey] ?? 0.0;
                final hasChange = _dailyChanges.containsKey(dateKey);

                return Expanded(
                  child: _buildDayCell(
                      date, dayNumber, change, hasChange, hideAmounts),
                );
              }).toList(),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDayCell(DateTime date, int day, double change, bool hasChange,
      bool hideAmounts) {
    final colors = SureColors.of(context);
    final palette = colors.palette;
    final now = (widget.now ?? DateTime.now)();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;

    // Check if this date is selected
    final isSelected = _selectedDate != null &&
        _selectedDate!.year == date.year &&
        _selectedDate!.month == date.month &&
        _selectedDate!.day == date.day;

    final trend = SureMoney.trendForAmount(change);
    final tintAlpha =
        Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.14;
    final Color? fill = !hasChange || change == 0
        ? null
        : SureMoney.color(context, trend).withValues(alpha: tintAlpha);

    return Semantics(
      button: true,
      selected: isSelected,
      child: GestureDetector(
        key: ValueKey('calendarDay-$day'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _onDayCellTap(date),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(color: palette.textPrimary, width: 1.5)
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                day.toString(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                  color: isToday ? palette.link : palette.textPrimary,
                ),
              ),
              if (hasChange) ...[
                const SizedBox(height: 2),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: MoneyText(
                      MoneyMasker.mask(
                        _formatAmount(change),
                        hidden: hideAmounts,
                      ),
                      trend: trend,
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatAmount(double amount) {
    // Support up to 8 decimal places, but omit unnecessary trailing zeros
    final formatter = NumberFormat('#,##0.########');
    final sign = amount >= 0 ? '+' : '';
    return '$sign${formatter.format(amount)}';
  }

  /// The month's net change with a sign and the account's currency symbol,
  /// e.g. "+$1,234.5", keeping up to 8 decimals for crypto.
  String _formatTotal(double amount, String locale) {
    final currency = _selectedAccount?.currency;
    String symbol;
    try {
      symbol =
          NumberFormat.simpleCurrency(locale: locale, name: currency)
              .currencySymbol;
    } catch (_) {
      symbol = currency ?? '';
    }
    final formatter = NumberFormat('#,##0.########', locale);
    return '${amount >= 0 ? '+' : '-'}$symbol${formatter.format(amount.abs())}';
  }
}
