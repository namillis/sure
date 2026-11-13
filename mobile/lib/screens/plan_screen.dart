import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/server_features_provider.dart';
import '../theme/sure_colors.dart';
import '../widgets/ds/ds.dart';
import '../widgets/open_on_web_action.dart';
import 'app_tabs.dart';
import 'bills_screen.dart';
import 'budgets_screen.dart';
import 'goals_screen.dart';

enum PlanSection { budget, recurring, goals, bills }

/// The Plan tab: a large title "Plan" over a segmented control
/// Budget | Recurring | Goals ↗ | Bills.
///
/// The title scrolls away with the active segment's list while the segmented
/// control stays pinned under the bar, like the account page. Goals is native
/// on a Sure+ server with the `goals` feature and points to the web
/// elsewhere.
class PlanScreen extends StatefulWidget {
  const PlanScreen({
    super.key,
    this.budgetBuilder = _buildBudget,
    this.recurringBuilder = AppTabs.recurring,
    this.billsBuilder = _buildBills,
    this.goalsBuilder = _buildGoals,
  });

  /// Body of the Budget segment. Injected in tests.
  final WidgetBuilder budgetBuilder;

  /// Body of the Recurring segment. Defaults to [AppTabs.recurring].
  final WidgetBuilder recurringBuilder;

  /// Body of the Bills segment. Defaults to [BillsScreen].
  final WidgetBuilder billsBuilder;

  static Widget _buildBudget(BuildContext context) =>
      const BudgetsScreen(embedded: true);

  /// Body of the Goals segment on a server with the `goals` feature.
  /// Defaults to [GoalsScreen].
  final WidgetBuilder goalsBuilder;

  static Widget _buildBills(BuildContext context) => const BillsScreen();

  static Widget _buildGoals(BuildContext context) => const GoalsScreen();

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  PlanSection _section = PlanSection.budget;
  // Segments are built on first visit, then kept alive, so a segment's
  // network load only starts when the user opens it.
  final Set<PlanSection> _visited = {PlanSection.budget};

  Widget _body(BuildContext context, PlanSection section) {
    final l = AppLocalizations.of(context);
    switch (section) {
      case PlanSection.budget:
        return widget.budgetBuilder(context);
      case PlanSection.recurring:
        return widget.recurringBuilder(context);
      case PlanSection.goals:
        if (_nativeGoals(context)) return widget.goalsBuilder(context);
        return WebOnlyView(
          icon: 'target', // Bundled Lucide icon with no SureIcons constant.
          title: l.shellPlanGoals,
          message: l.shellGoalsOnWeb,
          path: '/goals',
        );
      case PlanSection.bills:
        return widget.billsBuilder(context);
    }
  }

  bool _nativeGoals(BuildContext context) =>
      context
          .watch<ServerFeaturesProvider?>()
          ?.has(ServerFeaturesProvider.goals) ??
      false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    // Own Scaffold: segments such as Recurring show SnackBars.
    return Scaffold(
      backgroundColor: palette.surface,
      body: SureCollapsingHeader(
        title: l.shellNavPlan,
        pinned: _switcher(l, native: _nativeGoals(context)),
        pinnedKey: const ValueKey('planSectionSwitcher'),
        pinnedPadding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        body: Builder(builder: _sections),
      ),
    );
  }

  Widget _switcher(AppLocalizations l, {required bool native}) {
    const webMark = SureIcon(SureIcons.arrowUpRight, size: 12);
    return SureSegmentedControl<PlanSection>(
      selected: _section,
      onChanged: (section) => setState(() {
        _section = section;
        _visited.add(section);
      }),
      segments: [
        SureSegment(value: PlanSection.budget, label: l.shellPlanBudget),
        SureSegment(value: PlanSection.recurring, label: l.shellPlanRecurring),
        // Gap: SureSegment only takes a leading icon, so the web mark sits
        // before the label rather than after it.
        SureSegment(
            value: PlanSection.goals,
            label: l.shellPlanGoals,
            icon: native ? null : webMark),
        SureSegment(value: PlanSection.bills, label: l.shellPlanBills),
      ],
    );
  }

  /// The visited segments in an IndexedStack. Only the visible one gets the
  /// NestedScrollView's inner controller, so the hidden lists neither scroll
  /// along with it nor drive the title.
  Widget _sections(BuildContext context) {
    final inner = PrimaryScrollController.maybeOf(context);
    return IndexedStack(
      index: _section.index,
      children: [
        for (final section in PlanSection.values)
          if (!_visited.contains(section))
            const SizedBox.shrink()
          else if (section == _section && inner != null)
            PrimaryScrollController(
              controller: inner,
              child: _body(context, section),
            )
          else
            PrimaryScrollController.none(child: _body(context, section)),
      ],
    );
  }
}

/// Neutral placeholder for a section that isn't in the app yet.
class ComingSoonView extends StatelessWidget {
  const ComingSoonView({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SureEmptyState(
          icon: SureIcons.clock,
          title: l.shellComingSoon,
          body: l.shellComingSoonBody,
        ),
      ],
    );
  }
}

/// An empty state explaining a feature lives on the web, with a button that
/// opens [path] in the in-app web view.
class WebOnlyView extends StatelessWidget {
  const WebOnlyView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.path,
  });

  /// Lucide icon name.
  final String icon;
  final String title;
  final String message;
  final String path;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(
        top: 24,
        bottom: 24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        SureEmptyState(
          icon: icon,
          title: title,
          body: message,
          primaryLabel: l.shellOpenOnWeb,
          onPrimary: () => openWebFallback(context, title: title, path: path),
        ),
      ],
    );
  }
}
