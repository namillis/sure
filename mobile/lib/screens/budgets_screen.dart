import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/budget.dart';
import '../providers/auth_provider.dart';
import '../providers/budgets_provider.dart';
import '../providers/privacy_provider.dart';
import '../services/connectivity_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../widgets/budget_category_row.dart';
import '../widgets/budget_summary_card.dart';
import '../widgets/ds/ds.dart';
import '../widgets/open_on_web_action.dart';
import 'budget_category_transactions_screen.dart';

/// Monthly budget overview, matching the web Budgets page: month switcher,
/// a "left to spend" hero with a progress bar, then one panel of category
/// rows (subcategories nested under their parent) and the month's income.
/// Tapping a category opens its transactions for that budget period.
/// Read-only: budgets are edited on web.
class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({
    super.key,
    this.provider,
    this.accessTokenLoader,
    this.embedded = false,
  });

  /// True when shown inside a parent that already has its own title bar (the
  /// Plan tab), so the screen leaves out its own.
  final bool embedded;

  /// Injected for tests; otherwise the screen owns its provider.
  final BudgetsProvider? provider;

  /// Injected for tests; defaults to [AuthProvider.getValidAccessToken].
  final Future<String?> Function()? accessTokenLoader;

  /// The web budget page for the period starting [month]
  /// (`/budgets/nov-2026`, the Rails `Budget#to_param`).
  static String webPath(DateTime month) =>
      '/budgets/${DateFormat('MMM-yyyy', 'en').format(month).toLowerCase()}';

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

enum _CategoryFilter { all, overBudget }

class _BudgetsScreenState extends State<BudgetsScreen> {
  late final BudgetsProvider _provider;
  late final bool _ownsProvider;
  _CategoryFilter _filter = _CategoryFilter.all;

  @override
  void initState() {
    super.initState();
    _ownsProvider = widget.provider == null;
    _provider = widget.provider ??
        BudgetsProvider(
          isOffline: () {
            if (!mounted) return false;
            try {
              return context.read<ConnectivityService>().isOffline;
            } on ProviderNotFoundException {
              return false;
            }
          },
        );
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    if (_ownsProvider) _provider.dispose();
    super.dispose();
  }

  Future<String?> _accessToken() {
    final loader = widget.accessTokenLoader;
    if (loader != null) return loader();
    return context.read<AuthProvider>().getValidAccessToken();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final token = await _accessToken();
    if (!mounted) return;
    if (token == null) {
      _provider.markUnauthorized();
      return;
    }
    await _provider.loadMonth(accessToken: token, forceRefresh: forceRefresh);
  }

  void _changeMonth(VoidCallback change) {
    change();
    setState(() => _filter = _CategoryFilter.all);
    _load();
  }

  Future<void> _selectBudget(String budgetId) async {
    final token = await _accessToken();
    if (!mounted) return;
    if (token == null) {
      _provider.markUnauthorized();
      return;
    }
    setState(() => _filter = _CategoryFilter.all);
    await _provider.selectBudget(accessToken: token, budgetId: budgetId);
  }

  void _openCategory(Budget budget, BudgetCategory bc, List<String> ids) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BudgetCategoryTransactionsScreen(
          title: bc.name,
          periodLabel: _periodLabel(context, budget.startDate, budget),
          categoryIds: ids,
          startDate: budget.startDate,
          endDate: budget.endDate,
          categoryColor: bc.category.color,
          categoryIcon: bc.category.lucideIcon,
          accessTokenLoader: widget.accessTokenLoader,
        ),
      ),
    );
  }

  void _openWeb(DateTime month) {
    openWebFallback(
      context,
      title: AppLocalizations.of(context).budgetsTitle,
      path: BudgetsScreen.webPath(month),
    );
  }

  static String _periodLabel(BuildContext context, DateTime month, Budget? b) {
    // The server name covers families with a custom month start
    // ("Oct 15 - Nov 14, 2026"); otherwise format the month locally.
    if (b != null && b.name.isNotEmpty) return b.name;
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.yMMMM(locale).format(month);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<BudgetsProvider>.value(
      value: _provider,
      child: Consumer<BudgetsProvider>(
        builder: (context, provider, _) => _buildScaffold(context, provider),
      ),
    );
  }

  Widget _buildScaffold(BuildContext context, BudgetsProvider provider) {
    final l = AppLocalizations.of(context);
    final hideAmounts = context.watch<PrivacyProvider>().hidden;
    final children = [
      _buildMonthHeader(context, provider),
      ..._buildBody(context, provider, hideAmounts),
    ];

    if (!widget.embedded) {
      return SureLargeTitleScaffold(
        title: l.budgetsTitle,
        onRefresh: () => _load(forceRefresh: true),
        slivers: [SliverList.list(children: children)],
      );
    }
    return Scaffold(
      backgroundColor: SureColors.of(context).palette.surface,
      body: RefreshIndicator(
        onRefresh: () => _load(forceRefresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          children: children,
        ),
      ),
    );
  }

  Widget _buildMonthHeader(BuildContext context, BudgetsProvider provider) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    Widget chevron(String icon, String tooltip, VoidCallback? onPressed) =>
        IconButton(
          icon: SureIcon(
            icon,
            size: 20,
            color: onPressed == null ? palette.textSubdued : palette.textPrimary,
          ),
          tooltip: tooltip,
          onPressed: onPressed,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          chevron(
            SureIcons.chevronLeft,
            l.budgetsPreviousMonth,
            () => _changeMonth(provider.previousMonth),
          ),
          Expanded(
            child: Text(
              _periodLabel(context, provider.month, provider.budget),
              key: const ValueKey('budgetMonthLabel'),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: SureTokens.weightSemibold,
                color: palette.textPrimary,
              ),
            ),
          ),
          chevron(
            SureIcons.chevronRight,
            l.budgetsNextMonth,
            provider.canGoNext ? () => _changeMonth(provider.nextMonth) : null,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBody(
    BuildContext context,
    BudgetsProvider provider,
    bool hideAmounts,
  ) {
    final l = AppLocalizations.of(context);

    if (provider.isLoading && !provider.hasLoadedMonth) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 120),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    // A failed refresh keeps the month already loaded on screen (with a
    // banner), like the offline path; only a month never loaded gets the
    // full-screen error.
    switch (provider.refreshFailed ? null : provider.error) {
      case BudgetsLoadError.offline:
        return [
          _state(SureEmptyState(
            icon: SureIcons.cloudOff,
            title: l.budgetsOfflineTitle,
            body: l.budgetsOfflineMessage,
            secondaryLabel: l.commonTryAgain,
            onSecondary: () => _load(forceRefresh: true),
          )),
        ];
      case BudgetsLoadError.unauthorized:
        return [
          _state(SureEmptyState(
            icon: SureIcons.circleAlert,
            title: l.budgetsLoadFailed,
            body: l.budgetsSessionExpired,
          )),
        ];
      case BudgetsLoadError.failed:
        return [
          _state(SureEmptyState(
            icon: SureIcons.circleAlert,
            title: l.budgetsLoadFailed,
            secondaryLabel: l.commonTryAgain,
            onSecondary: () => _load(forceRefresh: true),
          )),
        ];
      case null:
        break;
    }

    if (!provider.hasLoadedMonth) return const [];

    final budget = provider.budget;
    if (budget == null) {
      final locale = Localizations.localeOf(context).toString();
      final month = provider.month;
      // "November" this year, "November 2025" otherwise.
      final monthLabel = month.year == provider.today.year
          ? DateFormat.MMMM(locale).format(month)
          : DateFormat.yMMMM(locale).format(month);
      return [
        _state(SureEmptyState(
          icon: SureIcons.chartPie,
          title: l.budgetsNoBudgetTitle(monthLabel),
          body: l.ds2pNoBudgetBody,
          primaryLabel: l.ds2pSetUpOnWeb,
          onPrimary: () => _openWeb(month),
        )),
      ];
    }

    final widgets = <Widget>[];
    const bannerMargin = EdgeInsets.fromLTRB(16, 4, 16, 8);

    if (provider.showingCachedWhileOffline) {
      widgets.add(SureBanner(
        icon: SureIcons.cloudOff,
        message: l.budgetsOfflineCached,
        margin: bannerMargin,
      ));
    }

    if (provider.refreshFailed) {
      widgets.add(SureBanner(
        icon: SureIcons.circleAlert,
        message: l.budgetsRefreshFailed,
        actionLabel: l.commonTryAgain,
        onAction: () => _load(forceRefresh: true),
        margin: bannerMargin,
      ));
    }

    if (provider.monthBudgets.length > 1) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < provider.monthBudgets.length; i++)
                SureChip(
                  label: l.budgetsBudgetNumber(i + 1),
                  selected: provider.monthBudgets[i].id == budget.id,
                  onSelected: (_) => _selectBudget(provider.monthBudgets[i].id),
                ),
            ],
          ),
        ),
      );
    }

    if (provider.isLoading) {
      widgets.add(const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: LinearProgressIndicator(minHeight: 2),
      ));
    }

    widgets.add(BudgetSummaryCard(
      budget: budget,
      hideAmounts: hideAmounts,
      now: provider.today,
    ));

    if (!budget.initialized) {
      widgets.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text(
          l.budgetsNotSetUpMessage,
          style: TextStyle(
            fontSize: 13,
            color: SureColors.of(context).palette.textSecondary,
          ),
        ),
      ));
    }

    widgets.addAll(_buildCategories(context, provider, budget, hideAmounts));

    if (budget.hasDerivedAmounts) {
      // One row in the category style; its title names it, so no header.
      widgets.add(const SizedBox(height: 16));
      widgets.add(SurePanel.rows(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        children: [BudgetIncomeRow(budget: budget, hideAmounts: hideAmounts)],
      ));
    }
    return widgets;
  }

  Widget _state(Widget child) => Padding(
        padding: const EdgeInsets.only(top: 48),
        child: Center(child: child),
      );

  List<Widget> _buildCategories(
    BuildContext context,
    BudgetsProvider provider,
    Budget budget,
    bool hideAmounts,
  ) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final groups = provider.visibleGroups;
    final overCount = provider.overBudgetCount;
    final filter = overCount == 0 ? _CategoryFilter.all : _filter;

    final rows = <Widget>[];
    void addRow(BudgetCategory bc, List<String> ids, {bool indented = false}) {
      rows.add(
        BudgetCategoryRow(
          key: ValueKey('budget-category-${bc.id}'),
          budgetCategory: bc,
          hideAmounts: hideAmounts,
          indented: indented,
          onTap: () => _openCategory(budget, bc, ids),
        ),
      );
    }

    for (final group in groups) {
      // Like the web, a parent that isn't itself visible only exists as the
      // container of its visible subcategories: no row, no indent.
      final showParent = provider.showsAllCategories || group.parent.isVisible;
      if (filter == _CategoryFilter.overBudget) {
        if (group.parent.isOverBudget) {
          addRow(group.parent, group.categoryIds);
        }
        for (final child in group.children.where((c) => c.isOverBudget)) {
          addRow(
            child,
            [child.category.id],
            indented: group.parent.isOverBudget,
          );
        }
      } else {
        if (showParent) addRow(group.parent, group.categoryIds);
        for (final child in group.children) {
          addRow(child, [child.category.id], indented: showParent);
        }
      }
    }

    return [
      _WebLinkSectionHeader(
        label: l.budgetsCategoriesTitle,
        linkLabel: l.ds2pEditOnWeb,
        onLink: () => _openWeb(budget.startDate),
      ),
      if (overCount > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SureSegmentedControl<_CategoryFilter>(
            segments: [
              SureSegment(value: _CategoryFilter.all, label: l.commonAll),
              SureSegment(
                value: _CategoryFilter.overBudget,
                label: l.budgetsFilterOverBudget(overCount),
              ),
            ],
            selected: filter,
            onChanged: (value) => setState(() => _filter = value),
          ),
        ),
      if (rows.isEmpty)
        SurePanel(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(14),
          child: Text(
            l.budgetsNoCategories,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
        )
      else
        SurePanel.rows(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          dividerIndent: SurePanel.iconRowDividerIndent,
          children: rows,
        ),
    ];
  }
}

/// A [SureSectionHeader]-styled header whose trailing link ends in a small
/// arrow-up-right, for links that leave the app.
///
/// Gap: SureSectionHeader takes an action label or an action icon, not both.
class _WebLinkSectionHeader extends StatelessWidget {
  const _WebLinkSectionHeader({
    required this.label,
    required this.linkLabel,
    required this.onLink,
  });

  final String label;
  final String linkLabel;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: SureTokens.weightMedium,
                  color: palette.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onLink,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 32),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      linkLabel,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: SureTokens.weightMedium,
                        color: palette.link,
                      ),
                    ),
                    const SizedBox(width: 2),
                    SureIcon(SureIcons.arrowUpRight,
                        size: 13, color: palette.link),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
