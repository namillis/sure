import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../models/goal.dart';
import '../providers/accounts_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/privacy_provider.dart';
import '../providers/server_features_provider.dart';
import '../services/goals_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../utils/money_masker.dart';
import '../widgets/budget_progress_bar.dart';
import '../widgets/ds/ds.dart';
import '../widgets/open_on_web_action.dart';
import 'goal_detail_screen.dart';
import 'goal_form_sheet.dart';

/// How the goal screens get a token and react to a 401. Defaults to the
/// app's [AuthProvider]; tests inject both.
class GoalsAuth {
  const GoalsAuth({this.accessTokenLoader, this.onUnauthorized});

  final Future<String?> Function()? accessTokenLoader;
  final Future<void> Function()? onUnauthorized;

  Future<String?> token(BuildContext context) {
    final loader = accessTokenLoader;
    if (loader != null) return loader();
    return context.read<AuthProvider>().getValidAccessToken();
  }

  Future<void> unauthorized(BuildContext context) async {
    final handler = onUnauthorized;
    if (handler != null) return handler();
    await context.read<AuthProvider>().logout();
  }
}

/// The user-facing text for a failed goals write: the read-only sign-in
/// message for 403 `insufficient_scope`, else the server's message.
String goalsErrorText(AppLocalizations l, Map<String, dynamic> result) {
  if (result['code'] == 'insufficient_scope') return l.spmReadOnlyAccess;
  final error = result['error']?.toString();
  return error == null || error.isEmpty ? l.manageActionFailed : error;
}

/// True while amounts should be masked (privacy mode). Pass `listen: false`
/// outside build (event handlers).
bool goalsAmountsHidden(BuildContext context, {bool listen = true}) =>
    Provider.of<PrivacyProvider?>(context, listen: listen)?.hidden ?? false;

String goalsMoney(BuildContext context, GoalMoney? money,
        {bool listen = true}) =>
    MoneyMasker.mask(money?.formatted ?? '--',
        hidden: goalsAmountsHidden(context, listen: listen));

/// The fundable accounts (Depository, Investment, Crypto: the server's
/// `Goal::FUNDABLE_ACCOUNT_TYPES`) from [accounts].
List<Account> goalFundableAccounts(List<Account> accounts) => [
      for (final a in accounts)
        if (const {'depository', 'investment', 'crypto'}
            .contains(a.accountType))
          a,
    ];

/// The localized label of a goal's `display_status`.
String goalStatusLabel(AppLocalizations l, String status) {
  switch (status) {
    case 'on_track':
      return l.spgStatusOnTrack;
    case 'behind':
      return l.spgStatusBehind;
    case 'reached':
      return l.spgStatusReached;
    case 'funded':
      return l.spgStatusFunded;
    case 'depleted':
      return l.spgStatusDepleted;
    case 'paused':
      return l.spgStatusPaused;
    case 'completed':
      return l.spgStatusCompleted;
    case 'archived':
      return l.spgStatusArchived;
    default:
      return l.spgStatusOpen;
  }
}

/// The token color of a goal's `display_status`.
Color goalStatusColor(SureTokenPalette palette, String status) {
  switch (status) {
    case 'on_track':
    case 'reached':
    case 'funded':
      return palette.success;
    case 'behind':
    case 'depleted':
      return palette.warning;
    case 'completed':
      return palette.link;
    default:
      return palette.textSecondary;
  }
}

/// "Due Apr 2027 · 5 months left", "Past due", "No date" or "Reserve".
String goalDueLine(BuildContext context, Goal goal) {
  final l = AppLocalizations.of(context);
  if (goal.isMaintained) return l.spgReserve;
  final date = goal.targetDate;
  if (date == null) return l.spgNoDate;
  final locale = Localizations.localeOf(context).toString();
  final due = l.spgDue(DateFormat.yMMM(locale).format(date));
  final left = goalTimeLeft(l, goal);
  return left == null ? due : '$due · $left';
}

/// "5 months left", "12 days left" or "Past due"; null for a goal that is
/// done, has no date, or is not running.
String? goalTimeLeft(AppLocalizations l, Goal goal) {
  final days = goal.daysLeft;
  if (days == null || goal.state != 'active' || goal.status == 'reached') {
    return null;
  }
  if (days < 0) return l.spgPastDue;
  if (days < 60) return l.spgDaysLeft(days);
  final months = goal.monthsRemaining?.round() ?? (days / 30).round();
  return l.spgMonthsLeft(months);
}

/// The status sub line: the server's localized `status_callout` (sentence
/// cased), else "Save $450/mo to catch up" when it names a catch-up amount.
String? goalCallout(BuildContext context, Goal goal) {
  final callout = goal.statusCallout?.trim();
  if (callout != null && callout.isNotEmpty) {
    return callout[0].toUpperCase() + callout.substring(1);
  }
  final catchUp = goal.catchUpAmount;
  if (catchUp != null && catchUp.isPositive && goal.state == 'active') {
    return AppLocalizations.of(context).spgCatchUp(goalsMoney(context, catchUp));
  }
  return null;
}

/// The goal's round icon in its color, falling back to its first letter
/// like a category.
class GoalIcon extends StatelessWidget {
  const GoalIcon({super.key, required this.goal, this.size = 32});

  final Goal goal;
  final double size;

  @override
  Widget build(BuildContext context) => SureCategoryIcon(
        name: goal.name.trim().isEmpty ? '?' : goal.name,
        color: goal.color,
        icon: goal.icon,
        size: size,
      );
}

/// A 6 px progress bar in the goal's color.
class GoalProgressBar extends StatelessWidget {
  const GoalProgressBar({super.key, required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) => BudgetProgressBar(
        fraction: goal.progressPercent / 100,
        color: parseCategoryColor(goal.color),
        hidden: goalsAmountsHidden(context),
      );
}

/// A goal in the list: icon, name, due line and progress, the bar, then
/// "$3,100 of $5,000" with the status, a callout and a pending-pledges chip.
class GoalCard extends StatelessWidget {
  const GoalCard({super.key, required this.goal, this.onTap});

  final Goal goal;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final hidden = goalsAmountsHidden(context);
    final callout = goalCallout(context, goal);
    final secondary = TextStyle(fontSize: 12, color: palette.textSecondary);

    return SurePanel(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GoalIcon(goal: goal),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goal.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: SureTokens.weightSemibold,
                        color: palette.textPrimary,
                      ),
                    ),
                    Text(
                      goalDueLine(context, goal),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: secondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                hidden ? MoneyMasker.maskedNumber : '${goal.progressPercent}%',
                style: SureMoney.tabular(TextStyle(
                  fontSize: 15,
                  fontWeight: SureTokens.weightSemibold,
                  color: palette.textPrimary,
                )),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GoalProgressBar(goal: goal),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: MoneyText(
                  l.spgAmountOf(goalsMoney(context, goal.currentAmount),
                      goalsMoney(context, goal.targetAmount)),
                  trend: MoneyTrend.neutral,
                  color: palette.textSecondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                goalStatusLabel(l, goal.displayStatus),
                key: ValueKey('goalStatus-${goal.id}'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: SureTokens.weightMedium,
                  color: goalStatusColor(palette, goal.displayStatus),
                ),
              ),
            ],
          ),
          if (callout != null) ...[
            const SizedBox(height: 2),
            Text(callout, style: secondary),
          ],
          if (goal.pendingPledgesCount > 0) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: SureChip(
                label: l.spgPendingPledges(goal.pendingPledgesCount),
                leading: SureIcon(SureIcons.clock,
                    size: 14, color: palette.textSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The Goals list header (feature `goals.summary`): three equal tiles (last
/// 30 days, needs this month, on track) and a "Saved $X / $Y" row. Amounts
/// shrink to fit a narrow tile and follow privacy masking.
class GoalsSummaryHeader extends StatelessWidget {
  const GoalsSummaryHeader({super.key, required this.summary});

  final GoalsSummary summary;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final s = summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _GoalsSummaryTile(
                    key: const ValueKey('goalsSummaryVelocity'),
                    label: l.sg2SummaryLast30,
                    value: goalsMoney(context, s.velocity30d),
                    money: true,
                    subtitle: l.sg2SummaryVsPrior(
                        goalsMoney(context, s.velocityPrior30d)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _GoalsSummaryTile(
                    key: const ValueKey('goalsSummaryNeeds'),
                    label: l.sg2SummaryNeedsThisMonth,
                    value: goalsMoney(context, s.needsThisMonth),
                    money: true,
                    subtitle: l.sg2SummaryBehind(s.behindCount),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _GoalsSummaryTile(
                    key: const ValueKey('goalsSummaryOnTrack'),
                    label: l.spgStatusOnTrack,
                    value: l.sg2SummaryOnTrackValue(
                        s.onTrackCount, s.trackedTotal),
                    subtitle: l.sg2SummaryReached(s.reachedCount),
                  ),
                ),
              ],
            ),
          ),
        ),
        SurePanel.rows(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          children: [
            SureListRow(
              key: const ValueKey('goalsSummarySaved'),
              title: l.sg2SummarySaved,
              trailing: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.6),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: MoneyText(
                    l.sg2SummarySavedValue(goalsMoney(context, s.saved),
                        goalsMoney(context, s.target)),
                    trend: MoneyTrend.neutral,
                    color: palette.textPrimary,
                    maxLines: 1,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GoalsSummaryTile extends StatelessWidget {
  const _GoalsSummaryTile({
    super.key,
    required this.label,
    required this.value,
    required this.subtitle,
    this.money = false,
  });

  final String label;
  final String value;
  final String subtitle;

  /// Mono with tabular figures (an amount) rather than plain text.
  final bool money;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final secondary = TextStyle(fontSize: 12, color: palette.textSecondary);
    const valueStyle = TextStyle(
        fontSize: 17, height: 1.2, fontWeight: SureTokens.weightSemibold);
    return SurePanel(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: secondary),
          const Spacer(),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: money
                ? MoneyText(value,
                    trend: MoneyTrend.neutral,
                    color: palette.textPrimary,
                    maxLines: 1,
                    style: valueStyle)
                : Text(value,
                    maxLines: 1,
                    style: SureMoney.tabular(
                        valueStyle.copyWith(color: palette.textPrimary))),
          ),
          const SizedBox(height: 2),
          Text(subtitle,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: secondary),
        ],
      ),
    );
  }
}

/// The Plan tab's Goals segment on a Sure+ server (feature `goals`): active
/// goals as cards, then paused, completed and archived goals behind
/// collapsed rows, in the server's display order. "+" opens the New goal
/// sheet; a card opens [GoalDetailScreen].
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({
    super.key,
    this.service,
    this.auth = const GoalsAuth(),
    this.accounts,
  });

  final GoalsService? service;
  final GoalsAuth auth;

  /// The user's accounts, for the "Fund from" list. Defaults to
  /// [AccountsProvider.accounts].
  final List<Account>? accounts;

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  late final GoalsService _service;
  List<Goal>? _goals;
  GoalsSummary? _summary;
  bool _loading = true;
  Map<String, dynamic>? _failure;
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? GoalsService();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  List<Account> get _accounts =>
      widget.accounts ?? context.read<AccountsProvider?>()?.accounts ?? const [];

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final token = await widget.auth.token(context);
    if (!mounted) return;
    if (token == null) {
      setState(() => _loading = false);
      return widget.auth.unauthorized(context);
    }
    final withSummary = context
            .read<ServerFeaturesProvider?>()
            ?.has(ServerFeaturesProvider.goalsSummary) ??
        false;
    final summaryRequest =
        withSummary ? _service.getSummary(accessToken: token) : null;
    final result = await _service.listGoals(accessToken: token);
    final summary = await summaryRequest;
    if (!mounted) return;
    if (result['error'] == 'unauthorized') {
      setState(() => _loading = false);
      return widget.auth.unauthorized(context);
    }
    setState(() {
      _loading = false;
      // A summary that fails to load is hidden; the list stays.
      _summary = summary?['success'] == true
          ? summary!['summary'] as GoalsSummary
          : null;
      if (result['success'] == true) {
        _goals = result['goals'] as List<Goal>;
        _failure = null;
      } else {
        _failure = result;
      }
    });
  }

  Future<void> _create() async {
    final created = await showGoalFormSheet(
      context,
      service: _service,
      auth: widget.auth,
      accounts: _accounts,
    );
    if (created == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).spgCreated)));
    _load();
  }

  Future<void> _open(Goal goal) async {
    final features = context.read<ServerFeaturesProvider?>();
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => GoalDetailScreen(
        goal: goal,
        service: _service,
        auth: widget.auth,
        accounts: _accounts,
        pledgesEnabled:
            features?.has(ServerFeaturesProvider.goalsPledges) ?? false,
        lifecycleEnabled:
            features?.has(ServerFeaturesProvider.goalsLifecycle) ?? false,
        onChanged: _load,
      ),
    ));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Scaffold(
      backgroundColor: palette.surface,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          // Clears the shell's see-through tab bar.
          padding: EdgeInsets.only(
            bottom: 32 + MediaQuery.paddingOf(context).bottom,
          ),
          children: _children(context),
        ),
      ),
    );
  }

  List<Widget> _children(BuildContext context) {
    final l = AppLocalizations.of(context);
    final goals = _goals;
    Widget state(Widget child) => Padding(
          padding: const EdgeInsets.only(top: 48),
          child: Center(child: child),
        );

    if (goals == null && _loading) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 120),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    final failure = _failure;
    if (failure?['code'] == 'feature_disabled') {
      return [
        state(SureEmptyState(
          key: const ValueKey('goalsPreviewDisabled'),
          icon: 'target', // Bundled Lucide icon with no SureIcons constant.
          title: l.spgPreviewTitle,
          body: l.spgPreviewBody,
          primaryLabel: l.spgPreviewAction,
          onPrimary: () => openWebFallback(context,
              title: l.shellPlanGoals, path: '/settings/preferences'),
        )),
      ];
    }
    if (goals == null) {
      return [
        state(SureEmptyState(
          key: const ValueKey('goalsLoadFailed'),
          icon: SureIcons.circleAlert,
          title: l.spgLoadFailed,
          body: failure?['error']?.toString(),
          secondaryLabel: l.commonTryAgain,
          onSecondary: _load,
        )),
      ];
    }

    if (goals.isEmpty) {
      return [
        state(SureEmptyState(
          key: const ValueKey('goalsEmpty'),
          icon: 'target',
          title: l.spgEmptyTitle,
          body: l.spgEmptyBody,
          primaryLabel: l.spgCreateFirst,
          onPrimary: _create,
        )),
      ];
    }

    final active = goals.where((g) => g.state == 'active').toList();
    final widgets = <Widget>[
      if (failure != null)
        SureBanner(
          icon: SureIcons.circleAlert,
          message: l.spgLoadFailed,
          actionLabel: l.commonTryAgain,
          onAction: _load,
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        ),
      if (_summary case final summary?)
        GoalsSummaryHeader(
            key: const ValueKey('goalsSummary'), summary: summary),
      SureSectionHeader(
        key: const ValueKey('goalsActiveHeader'),
        label: l.spgSectionActive(active.length),
        actionIcon: SureIcons.plus,
        actionSemanticLabel: l.spgNewGoal,
        onAction: _create,
      ),
      for (final goal in active)
        GoalCard(
          key: ValueKey('goal-${goal.id}'),
          goal: goal,
          onTap: () => _open(goal),
        ),
    ];

    for (final state in const ['paused', 'completed', 'archived']) {
      final group = goals.where((g) => g.state == state).toList();
      if (group.isEmpty) continue;
      final open = _expanded.contains(state);
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SurePanel.rows(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          children: [
            Semantics(
              expanded: open,
              child: SureListRow(
                key: ValueKey('goalsSection-$state'),
                title: _sectionLabel(l, state, group.length),
                trailing: SureIcon(
                  open ? SureIcons.chevronUp : SureIcons.chevronDown,
                  size: 18,
                  color: SureColors.of(context).palette.textSecondary,
                ),
                onTap: () => setState(() {
                  if (!_expanded.remove(state)) _expanded.add(state);
                }),
              ),
            ),
          ],
        ),
      ));
      if (open) {
        for (final goal in group) {
          widgets.add(GoalCard(
            key: ValueKey('goal-${goal.id}'),
            goal: goal,
            onTap: () => _open(goal),
          ));
        }
      }
    }
    return widgets;
  }

  static String _sectionLabel(AppLocalizations l, String state, int count) {
    switch (state) {
      case 'paused':
        return l.spgSectionPaused(count);
      case 'completed':
        return l.spgSectionCompleted(count);
      default:
        return l.spgSectionArchived(count);
    }
  }
}
