import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/offline_transaction.dart';
import '../../models/transaction.dart';
import '../../theme/sure_colors.dart';
import '../../theme/sure_theme.dart';
import '../../widgets/ds/ds.dart';

/// Debug-only gallery of every shared redesign component in its states, for
/// Simulator screenshots in light and dark. Nothing in the app links here;
/// open it from a temporary hook. In release builds it renders nothing.
///
/// The sample names and amounts are fixtures, not app copy, so they are not
/// localized.
class DsGalleryScreen extends StatefulWidget {
  const DsGalleryScreen({super.key});

  @override
  State<DsGalleryScreen> createState() => _DsGalleryScreenState();
}

class _DsGalleryScreenState extends State<DsGalleryScreen> {
  /// Null follows the app; otherwise forces light or dark.
  Brightness? _forced;
  String _range = '3M';
  String _tab = 'holdings';
  final Set<String> _chips = {'This month'};
  bool _selected = true;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    final page = _GalleryPage(state: this);
    if (_forced == null) return page;
    return Theme(
      data: _forced == Brightness.dark ? SureTheme.dark : SureTheme.light,
      child: page,
    );
  }

  void update(VoidCallback fn) => setState(fn);

  void _toggleBrightness(Brightness current) => setState(() {
        _forced =
            current == Brightness.dark ? Brightness.light : Brightness.dark;
      });

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _GalleryPage extends StatelessWidget {
  const _GalleryPage({required this.state});

  final _DsGalleryScreenState state;

  static Transaction _tx(
    String name,
    String amount, {
    String nature = 'expense',
    String? category,
  }) =>
      Transaction(
        id: name,
        accountId: 'demo',
        name: name,
        date: '2026-11-11',
        amount: amount,
        currency: 'USD',
        nature: nature,
        categoryName: category,
      );

  @override
  Widget build(BuildContext context) {
    final colors = SureColors.of(context);
    final palette = colors.palette;
    final brightness = Theme.of(context).brightness;
    final now = DateTime(2026, 11, 11);

    Widget section(String label, Widget child) => SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SureSectionHeader(
                  label: label,
                  padding: const EdgeInsets.fromLTRB(0, 20, 0, 6),
                ),
                child,
              ],
            ),
          ),
        );

    final categories = SureIcons.category.toList()..sort();

    return SureLargeTitleScaffold(
      title: 'Design gallery',
      subtitle: 'Wave 1 components · ${brightness.name}',
      actions: [
        SureNavIconButton(
          icon: brightness == Brightness.dark ? SureIcons.eye : SureIcons.eyeOff,
          semanticLabel: 'Toggle light/dark',
          onPressed: () => state._toggleBrightness(brightness),
        ),
        SureNavIconButton(
          icon: SureIcons.plus,
          semanticLabel: 'Add',
          onPressed: () => state._toast(context, 'Add tapped'),
        ),
      ],
      slivers: [
        section(
          'Hero amount and change line',
          SurePanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Net worth',
                    style:
                        TextStyle(fontSize: 13, color: palette.textSecondary)),
                const SizedBox(height: 4),
                const MoneyText(
                  r'$858,212.40',
                  trend: MoneyTrend.neutral,
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
                ),
                Row(
                  children: [
                    const MoneyText(
                      r'+$74,483.90 (9.5%)',
                      trend: MoneyTrend.inflow,
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(width: 6),
                    Text('3M',
                        style: TextStyle(
                            fontSize: 13, color: palette.textSubdued)),
                  ],
                ),
                const MoneyText(
                  r'-$1,204.11 (0.4%)',
                  trend: MoneyTrend.outflow,
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        section(
          'Banners',
          const Column(
            children: [
              SureBanner(
                icon: SureIcons.cloudOff,
                message: 'Offline · showing data from 2h ago',
              ),
              SizedBox(height: 8),
              SureBanner(
                message:
                    'A very long warning that has to fit on one line and ellipsize at the end',
              ),
            ],
          ),
        ),
        section(
          'Chips',
          Wrap(
            spacing: 8,
            children: [
              for (final label in ['This month', '1M', '3M'])
                SureChip(
                  label: label,
                  selected: state._chips.contains(label),
                  onSelected: (on) => state.update(() {
                    on ? state._chips.add(label) : state._chips.remove(label);
                  }),
                ),
              SureChip(label: 'Category', dropdown: true, onSelected: (_) {}),
              const SureChip(label: 'Disabled', enabled: false),
            ],
          ),
        ),
        section(
          'Segmented controls',
          Column(
            children: [
              SureSegmentedControl<String>(
                selected: state._range,
                onChanged: (v) => state.update(() => state._range = v),
                segments: const [
                  SureSegment(value: '1W', label: '1W'),
                  SureSegment(value: '1M', label: '1M'),
                  SureSegment(value: '3M', label: '3M'),
                  SureSegment(value: '1Y', label: '1Y'),
                  SureSegment(value: 'All', label: 'All'),
                ],
              ),
              const SizedBox(height: 8),
              SureSegmentedControl<String>(
                selected: state._tab,
                onChanged: (v) => state.update(() => state._tab = v),
                segments: const [
                  SureSegment(value: 'holdings', label: 'Holdings'),
                  SureSegment(value: 'activity', label: 'Activity'),
                  SureSegment(value: 'transactions', label: 'Transactions'),
                ],
              ),
            ],
          ),
        ),
        section(
          'Search field',
          const SureSearchField(hintText: 'Search transactions'),
        ),
        section(
          'Panel rows',
          SurePanel.rows(
            dividerIndent: SurePanel.iconRowDividerIndent,
            children: [
              SureListRow(
                leading: const SureCategoryIcon(
                    name: 'Shopping', color: '#3b82f6', icon: 'shopping-cart'),
                title: 'Category',
                value: 'Shopping',
                showChevron: true,
                onTap: () {},
              ),
              const SureListRow(
                leading: SureCategoryIcon(
                    name: 'Cash', color: '#4da568', icon: 'wallet'),
                title: 'Cash · 3',
                subtitle: '(1 empty)',
                trailing: MoneyText(r'$12,040.00', trend: MoneyTrend.neutral),
              ),
              const SureListRow(
                leading: SureCategoryIcon(
                    name: 'Loans', color: '#e11d48', icon: 'credit-card'),
                title:
                    'A very long account group title that must ellipsize cleanly',
                subtitle:
                    'And a long subtitle under it that also ellipsizes at the end',
                showChevron: true,
              ),
              SureListRow(
                title: 'Open on the web',
                titleColor: palette.link,
                trailing: SureIcon(SureIcons.arrowUpRight,
                    size: 16, color: palette.link),
                onTap: () {},
              ),
            ],
          ),
        ),
        section(
          'Destructive row',
          SurePanel.rows(children: [
            SureListRow(
              title: 'Delete transaction',
              destructive: true,
              onTap: () => state._toast(context, 'Delete tapped'),
            ),
          ]),
        ),
        section(
          'Section header actions',
          SurePanel(
            child: Column(
              children: [
                SureSectionHeader(
                    label: 'Recent', actionLabel: 'See all', onAction: () {}),
                SureSectionHeader(
                  label: 'Accounts',
                  actionIcon: SureIcons.plus,
                  actionSemanticLabel: 'Add account',
                  onAction: () {},
                ),
              ],
            ),
          ),
        ),
        section(
          'Category icons and fallbacks',
          const SurePanel(
            padding: EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SureCategoryIcon(
                    name: 'Food', color: '#f97316', icon: 'utensils'),
                SureCategoryIcon(name: 'Home', color: '#b45309', icon: 'home'),
                SureCategoryIcon(
                    name: 'Zebra', color: '#6366f1', icon: 'not-a-lucide-icon'),
                SureCategoryIcon(),
                SureCategoryIcon.transfer(),
                SureCategoryIcon.split(),
                SureCategoryIcon(
                    name: 'Groceries',
                    color: '#407706',
                    icon: 'shopping-bag',
                    size: SureCategoryIcon.heroSize),
                SureCategoryIcon(
                    name: 'Groceries',
                    color: '#407706',
                    size: SureCategoryIcon.dotSize),
                SureCategoryIcon(size: SureCategoryIcon.dotSize),
              ],
            ),
          ),
        ),
        section(
          'Every server category icon (${categories.length})',
          SurePanel(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (i, icon) in categories.indexed)
                  Tooltip(
                    message: icon,
                    child: SureCategoryIcon(
                      name: icon,
                      icon: icon,
                      color: const [
                        '#e99537',
                        '#4da568',
                        '#6471eb',
                        '#db5a54',
                        '#df4e92',
                        '#c44fe9',
                        '#61c9ea',
                      ][i % 7],
                    ),
                  ),
              ],
            ),
          ),
        ),
        section(
          'Transaction rows (swipe left)',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SureDayHeader.forDay(context, now,
                  total: r'-$61.05', background: false, now: now),
              SurePanel.rows(
                dividerIndent: SurePanel.iconRowDividerIndent,
                children: [
                  SureTransactionRow(
                    transaction: _tx('Whole Foods', r'$54.20',
                        category: 'Groceries'),
                    accountName: 'Chase Sapphire',
                    accountType: 'credit_card',
                    categoryColor: '#407706',
                    categoryIcon: 'shopping-bag',
                    hideAmount: false,
                    onTap: () => state._toast(context, 'Row tapped'),
                    onCategorize: () => state._toast(context, 'Categorize'),
                    onDelete: () => state._toast(context, 'Delete'),
                  ),
                  SureTransactionRow(
                    transaction: _tx('Payroll', r'-$3,200.00',
                        nature: 'income', category: 'Income'),
                    accountName: 'Checking',
                    accountType: 'depository',
                    categoryColor: '#22c55e',
                    categoryIcon: 'circle-dollar-sign',
                    hideAmount: false,
                    onCategorize: () {},
                    onDelete: () {},
                  ),
                  SureTransactionRow(
                    transaction: _tx('Payment to card', r'$500.00'),
                    accountName: 'Checking',
                    accountType: 'depository',
                    isTransfer: true,
                    hideAmount: false,
                  ),
                  SureTransactionRow(
                    transaction: _tx('Costco', r'$212.48'),
                    accountName: 'Checking',
                    accountType: 'depository',
                    isSplitParent: true,
                    hideAmount: false,
                  ),
                  SureTransactionRow(
                    transaction: _tx(
                        'A merchant with an extremely long name that ellipsizes',
                        r'$6.85'),
                    accountName: 'An account with a long name too',
                    accountType: 'depository',
                    hideAmount: false,
                  ),
                  SureTransactionRow(
                    transaction:
                        _tx('Coffee', r'$4.50', category: 'Coffee shops'),
                    showAccount: false,
                    accountType: 'depository',
                    categoryColor: '#b45309',
                    categoryIcon: 'coffee',
                    syncStatus: SyncStatus.pending,
                    hideAmount: false,
                  ),
                  SureTransactionRow(
                    transaction: _tx('Parking', r'$12.00', category: 'Car'),
                    showAccount: false,
                    accountType: 'depository',
                    categoryColor: '#0ea5e9',
                    categoryIcon: 'circle-parking',
                    syncStatus: SyncStatus.failed,
                    hideAmount: false,
                  ),
                  SureTransactionRow(
                    transaction: _tx('Hidden amount', r'$99.99',
                        category: 'Shopping'),
                    accountType: 'depository',
                    categoryColor: '#3b82f6',
                    categoryIcon: 'shopping-cart',
                    hideAmount: true,
                  ),
                ],
              ),
              const SureDayHeader(
                  label: 'Selection mode', total: r'$0.00', background: false),
              SurePanel.rows(
                dividerIndent: SurePanel.iconRowDividerIndent,
                children: [
                  SureTransactionRow(
                    transaction: _tx('Selected row', r'$10.00',
                        category: 'Fees'),
                    accountType: 'depository',
                    selectionMode: true,
                    selected: state._selected,
                    hideAmount: false,
                    onTap: () =>
                        state.update(() => state._selected = !state._selected),
                  ),
                  SureTransactionRow(
                    transaction: _tx('Unselected row', r'$20.00',
                        category: 'Fees'),
                    accountType: 'depository',
                    selectionMode: true,
                    hideAmount: false,
                  ),
                ],
              ),
            ],
          ),
        ),
        section(
          'Empty state',
          SurePanel(
            child: SureEmptyState(
              icon: SureIcons.landmark,
              title: 'No accounts yet',
              body:
                  'Connect a bank on the web, or add a manual account like a house or car.',
              primaryLabel: 'Connect on the web',
              onPrimary: () {},
              secondaryLabel: 'Add a manual account',
              onSecondary: () {},
            ),
          ),
        ),
        section(
          'Empty state (no results)',
          SurePanel(
            child: SureEmptyState(
              icon: SureIcons.search,
              title: 'No matches for "starbuck"',
              body: 'Try fewer filters or a longer date range.',
              secondaryLabel: 'Clear filters',
              onSecondary: () {},
            ),
          ),
        ),
        section(
          'Dates',
          SurePanel.rows(children: [
            for (final (label, date) in [
              ('Today', now),
              ('Yesterday', DateTime(2026, 11, 10)),
              ('This year', DateTime(2026, 3, 4)),
              ('Last year', DateTime(2025, 12, 31)),
            ])
              SureListRow(
                title: label,
                value: SureDates.relativeDayOf(context, date, now: now),
              ),
            SureListRow(
              title: 'Range',
              value: SureDates.rangeOf(
                  context, DateTime(2026, 11, 1), now, now: now),
            ),
            SureListRow(
              title: 'Full (chart scrub)',
              value: SureDates.fullOf(context, DateTime(2026, 11, 5)),
            ),
          ]),
        ),
        section(
          'Sheet',
          SurePanel.rows(children: [
            SureListRow(
              title: 'Open a Cancel/Save sheet',
              showChevron: true,
              onTap: () => showSureSheet<void>(
                context: context,
                builder: (sheetContext) => SureSheet(
                  title: 'Transaction',
                  onAction: () {
                    SureHaptics.success();
                    Navigator.of(sheetContext).pop();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SurePanel.rows(children: [
                      const SureListRow(
                          title: 'Merchant',
                          value: 'Whole Foods',
                          showChevron: true),
                      const SureListRow(
                          title: 'Date', value: 'Nov 6', showChevron: true),
                      SureListRow(
                        title: 'Open on the web',
                        titleColor: SureColors.of(sheetContext).palette.link,
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
        section(
          'Tab bar',
          SurePanel(
            child: SureTabBar(
              currentIndex: 0,
              onSelected: (_) {},
              items: const [
                SureTabItem(icon: SureIcons.house, label: 'Home'),
                SureTabItem(icon: SureIcons.receipt, label: 'Activity'),
                SureTabItem(icon: SureIcons.chartPie, label: 'Plan'),
                SureTabItem(icon: SureIcons.trendingUp, label: 'Invest'),
                SureTabItem(
                    icon: SureIcons.messageCircle, label: 'Assistant'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
