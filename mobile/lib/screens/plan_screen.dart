import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../widgets/open_on_web_action.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_card.dart';
import '../widgets/sure_segmented_control.dart';
import 'app_tabs.dart';
import 'budgets_screen.dart';

enum PlanSection { budget, recurring, goals, bills }

/// The Plan tab: Budget | Recurring | Goals | Bills.
///
/// Goals and Bills have no API yet, so they point to the web.
class PlanScreen extends StatefulWidget {
  const PlanScreen({
    super.key,
    this.budgetBuilder = _buildBudget,
    this.recurringBuilder = AppTabs.recurring,
  });

  /// Body of the Budget segment. Injected in tests.
  final WidgetBuilder budgetBuilder;

  /// Body of the Recurring segment. Defaults to [AppTabs.recurring].
  final WidgetBuilder recurringBuilder;

  static Widget _buildBudget(BuildContext context) => const BudgetsScreen();

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
        return WebOnlyView(
          icon: Icons.flag_outlined,
          title: l.shellPlanGoals,
          message: l.shellGoalsOnWeb,
          path: '/goals',
        );
      case PlanSection.bills:
        return WebOnlyView(
          icon: Icons.event_note_outlined,
          title: l.shellPlanBills,
          message: l.shellBillsOnWeb,
          path: '/bills',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SureSpacing.xl,
            SureSpacing.md,
            SureSpacing.xl,
            SureSpacing.md,
          ),
          child: SureSegmentedControl<PlanSection>(
            selected: _section,
            onChanged: (section) => setState(() {
              _section = section;
              _visited.add(section);
            }),
            segments: [
              SureSegment(value: PlanSection.budget, label: l.shellPlanBudget),
              SureSegment(
                  value: PlanSection.recurring, label: l.shellPlanRecurring),
              SureSegment(value: PlanSection.goals, label: l.shellPlanGoals),
              SureSegment(value: PlanSection.bills, label: l.shellPlanBills),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _section.index,
            children: [
              for (final section in PlanSection.values)
                _visited.contains(section)
                    ? _body(context, section)
                    : const SizedBox.shrink(),
            ],
          ),
        ),
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
    final palette = SureColors.of(context).palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SureSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_empty, size: 48, color: palette.textSubdued),
            const SizedBox(height: SureSpacing.xl),
            Text(
              l.shellComingSoon,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SureSpacing.md),
            Text(
              l.shellComingSoonBody,
              style: TextStyle(color: palette.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// A card explaining a feature lives on the web, with a button that opens
/// [path] in the in-app web view.
class WebOnlyView extends StatelessWidget {
  const WebOnlyView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.path,
  });

  final IconData icon;
  final String title;
  final String message;
  final String path;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    return ListView(
      padding: const EdgeInsets.all(SureSpacing.xl),
      children: [
        SureCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 32, color: palette.textPrimary),
              const SizedBox(height: SureSpacing.lg),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: SureSpacing.md),
              Text(message, style: TextStyle(color: palette.textSecondary)),
              const SizedBox(height: SureSpacing.xl),
              SureButton(
                label: l.shellOpenOnWeb,
                leading: const Icon(Icons.language, size: 18),
                fullWidth: true,
                onPressed: () =>
                    openWebFallback(context, title: title, path: path),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
