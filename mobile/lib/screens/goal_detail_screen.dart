import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../models/goal.dart';
import '../services/goals_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../widgets/ds/ds.dart';
import '../widgets/manage_widgets.dart';
import '../widgets/open_on_web_action.dart';
import '../widgets/sure_button.dart';
import 'goal_consume_sheet.dart';
import 'goal_form_sheet.dart';
import 'goals_screen.dart';
import 'pledge_sheet.dart';

/// One goal (feature `goals`): a centered hero with the amount and bar, "I
/// saved toward this" (feature `goals.pledges`, goals with linked accounts),
/// pending pledges with Extend and cancel, the funding accounts, the plan
/// figures, Edit, the lifecycle actions (feature `goals.lifecycle`; a web
/// link without it), and Delete.
class GoalDetailScreen extends StatefulWidget {
  const GoalDetailScreen({
    super.key,
    required this.goal,
    required this.service,
    this.auth = const GoalsAuth(),
    this.accounts = const [],
    this.pledgesEnabled = false,
    this.lifecycleEnabled = false,
    this.onChanged,
  });

  final Goal goal;
  final GoalsService service;
  final GoalsAuth auth;

  /// For the edit sheet's "Fund from" list.
  final List<Account> accounts;
  final bool pledgesEnabled;

  /// Feature `goals.lifecycle`: the native action rows replace the web link.
  final bool lifecycleEnabled;

  /// Called after a lifecycle action or spend changed the goal, so the list
  /// behind this screen reloads.
  final VoidCallback? onChanged;

  @override
  State<GoalDetailScreen> createState() => _GoalDetailScreenState();
}

class _GoalDetailScreenState extends State<GoalDetailScreen> {
  late Goal _goal = widget.goal;
  bool _scrolled = false;
  bool _deleting = false;
  String? _busyPledgeId;
  String? _busyAction;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  /// Runs [call] with a token; handles a 401 and returns null then.
  Future<Map<String, dynamic>?> _authed(
      Future<Map<String, dynamic>> Function(String token) call) async {
    final token = await widget.auth.token(context);
    if (!mounted) return null;
    if (token == null) {
      await widget.auth.unauthorized(context);
      return null;
    }
    final result = await call(token);
    if (!mounted) return null;
    if (result['error'] == 'unauthorized') {
      await widget.auth.unauthorized(context);
      return null;
    }
    return result;
  }

  Future<void> _refresh() async {
    final result = await _authed(
        (t) => widget.service.getGoal(accessToken: t, id: _goal.id));
    if (result == null || result['success'] != true) return;
    setState(() => _goal = result['goal'] as Goal);
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _edit() async {
    final l = AppLocalizations.of(context);
    final saved = await showGoalFormSheet(
      context,
      service: widget.service,
      auth: widget.auth,
      accounts: widget.accounts,
      goal: _goal,
    );
    if (saved == null || !mounted) return;
    setState(() => _goal = saved);
    _snack(l.spgSaved);
  }

  Future<void> _pledge() async {
    final l = AppLocalizations.of(context);
    final updated = await showPledgeSheet(
      context,
      service: widget.service,
      auth: widget.auth,
      goal: _goal,
    );
    if (updated == null || !mounted) return;
    setState(() => _goal = updated);
    _snack(l.spgPledgeSaved);
  }

  Future<void> _renew(GoalPledge pledge) async {
    final l = AppLocalizations.of(context);
    setState(() {
      _busyPledgeId = pledge.id;
      _error = null;
    });
    final result = await _authed((t) => widget.service.renewPledge(
        accessToken: t, goalId: _goal.id, pledgeId: pledge.id));
    if (!mounted) return;
    setState(() {
      _busyPledgeId = null;
      if (result?['success'] == true) {
        _goal = result!['goal'] as Goal;
      } else if (result != null) {
        _error = goalsErrorText(l, result);
      }
    });
    if (result?['success'] == true) _snack(l.spgPledgeExtended);
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
    String? cancel,
    bool destructive = true,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final dl = AppLocalizations.of(context);
        final palette = SureColors.of(context).palette;
        return AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(cancel ?? dl.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: destructive
                  ? TextButton.styleFrom(foregroundColor: palette.destructive)
                  : null,
              child: Text(action),
            ),
          ],
        );
      },
    );
    return confirmed == true && mounted;
  }

  Future<void> _cancelPledge(GoalPledge pledge) async {
    final l = AppLocalizations.of(context);
    final ok = await _confirm(
      title: l.spgPledgeCancelTitle,
      body: l.spgPledgeCancelBody(
          goalsMoney(context, pledge.amount, listen: false)),
      action: l.spgPledgeCancelConfirm,
      cancel: l.spgPledgeKeep,
    );
    if (!ok) return;
    setState(() {
      _busyPledgeId = pledge.id;
      _error = null;
    });
    final result = await _authed((t) => widget.service.cancelPledge(
        accessToken: t, goalId: _goal.id, pledgeId: pledge.id));
    if (!mounted) return;
    setState(() {
      _busyPledgeId = null;
      if (result?['success'] == true) {
        _goal = result!['goal'] as Goal;
      } else if (result != null) {
        _error = goalsErrorText(l, result);
      }
    });
    if (result?['success'] == true) _snack(l.spgPledgeCancelled);
  }

  Future<void> _delete() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await _confirm(
      title: l.spgDeleteTitle,
      body: l.spgDeleteBody(_goal.name),
      action: l.commonDelete,
    );
    if (!ok) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    final result = await _authed(
        (t) => widget.service.deleteGoal(accessToken: t, id: _goal.id));
    if (!mounted) return;
    if (result?['success'] == true) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(l.spgDeleted)));
      return;
    }
    setState(() {
      _deleting = false;
      if (result != null) _error = goalsErrorText(l, result);
    });
  }

  /// The lifecycle rows in their fixed order, filtered by the goal's
  /// `available_actions`.
  static const _actionOrder = [
    'consume',
    'pause',
    'resume',
    'complete',
    'reopen',
    'archive',
    'unarchive',
  ];

  static String _actionLabel(AppLocalizations l, String action) {
    switch (action) {
      case 'consume':
        return l.sg2ActionConsume;
      case 'pause':
        return l.sg2ActionPause;
      case 'resume':
        return l.sg2ActionResume;
      case 'complete':
        return l.sg2ActionComplete;
      case 'reopen':
        return l.sg2ActionReopen;
      case 'archive':
        return l.sg2ActionArchive;
      default:
        return l.sg2ActionUnarchive;
    }
  }

  static String _actionDone(AppLocalizations l, String action) {
    switch (action) {
      case 'pause':
        return l.sg2Paused;
      case 'resume':
        return l.sg2Resumed;
      case 'complete':
        return l.sg2Completed;
      case 'reopen':
        return l.sg2Reopened;
      case 'archive':
        return l.sg2Archived;
      default:
        return l.sg2Unarchived;
    }
  }

  Future<void> _consume() async {
    final l = AppLocalizations.of(context);
    final updated = await showGoalConsumeSheet(
      context,
      service: widget.service,
      auth: widget.auth,
      goal: _goal,
    );
    if (updated == null || !mounted) return;
    setState(() => _goal = updated);
    widget.onChanged?.call();
    _snack(l.sg2Consumed);
  }

  Future<void> _transition(String action) async {
    final l = AppLocalizations.of(context);
    if (action == 'complete' || action == 'archive') {
      final complete = action == 'complete';
      final ok = await _confirm(
        title: complete ? l.sg2CompleteTitle : l.sg2ArchiveTitle,
        body: complete ? l.sg2CompleteBody : l.sg2ArchiveBody,
        action: _actionLabel(l, action),
        destructive: false,
      );
      if (!ok) return;
    }
    setState(() {
      _busyAction = action;
      _error = null;
    });
    final result = await _authed((t) => widget.service
        .transitionGoal(accessToken: t, id: _goal.id, action: action));
    if (!mounted) return;
    final ok = result?['success'] == true;
    setState(() {
      _busyAction = null;
      if (ok) {
        _goal = result!['goal'] as Goal;
      } else if (result != null) {
        _error = goalsErrorText(l, result);
      }
    });
    if (!ok) return;
    widget.onChanged?.call();
    _snack(_actionDone(l, action));
  }

  Widget _actionsPanel(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final available = _goal.availableActions.toSet();
    final idle = _busyAction == null && !_deleting;
    return SurePanel.rows(
      key: const ValueKey('goalActions'),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        for (final action in _actionOrder)
          if (available.contains(action))
            SureListRow(
              key: ValueKey('goalAction-$action'),
              title: _actionLabel(l, action),
              titleColor: palette.link,
              trailing: _busyAction == action
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: !idle
                  ? null
                  : action == 'consume'
                      ? _consume
                      : () => _transition(action),
            ),
      ],
    );
  }

  void _openWeb() {
    openWebFallback(
      context,
      title: _goal.name,
      path: '/goals/${Uri.encodeComponent(_goal.id)}',
      backLabel: _goal.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return Scaffold(
      backgroundColor: palette.surface,
      body: Column(
        children: [
          SureNavBar(
            title: _goal.name,
            showTitle: _scrolled,
            leading: canPop ? SureBackButton(label: l.shellNavPlan) : null,
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: (n) {
                  final scrolled = n.metrics.pixels > 120;
                  if (scrolled != _scrolled) {
                    setState(() => _scrolled = scrolled);
                  }
                  return false;
                },
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.only(
                      bottom: 32 + MediaQuery.paddingOf(context).bottom,
                    ),
                    children: _children(context),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _children(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final goal = _goal;
    const margin = EdgeInsets.symmetric(horizontal: 16);
    final pledges = goal.openPledges;
    final canPledge = widget.pledgesEnabled && goal.linkedAccounts.isNotEmpty;

    final plan = <Widget>[
      if (goal.monthlyTargetAmount != null)
        _amountRow(l.spgMonthlyTarget, goalsMoney(context, goal.monthlyTargetAmount)),
      if (goal.pace != null)
        _amountRow(l.spgPace, l.spgPerMonth(goalsMoney(context, goal.pace))),
      if (goal.projectedCompletionDate != null)
        SureListRow(
          title: l.spgProjected,
          value: SureDates.fullOf(context, goal.projectedCompletionDate!),
        ),
      if (goalTimeLeft(l, goal) case final left?)
        SureListRow(title: l.spgTimeLeft, value: left),
    ];

    return [
      _hero(context),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: ManageErrorText(_error!),
        ),
      if (canPledge)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: SureButton(
            key: const ValueKey('goalPledgeButton'),
            label: l.spgSavedToward,
            leading: SureIcon(SureIcons.plus, size: 16, color: palette.textInverse),
            fullWidth: true,
            size: SureButtonSize.lg,
            onPressed: _deleting ? null : _pledge,
          ),
        ),
      if (pledges.isNotEmpty) ...[
        SureSectionHeader(label: l.spgPendingHeader),
        SurePanel.rows(
          margin: margin,
          children: [for (final p in pledges) _pledgeRow(context, p)],
        ),
      ],
      if (goal.linkedAccounts.isNotEmpty) ...[
        SureSectionHeader(label: l.spgFundingHeader),
        SurePanel.rows(
          margin: margin,
          children: [
            for (final a in goal.linkedAccounts)
              SureListRow(
                key: ValueKey('goalFunding-${a.id}'),
                title: a.name,
                subtitle: a.wholeAccount ? l.spgWholeBalance : null,
                trailing: MoneyText(
                  goalsMoney(
                      context,
                      a.wholeAccount
                          ? a.backingAmount
                          : a.allocatedAmount ?? a.backingAmount),
                  trend: MoneyTrend.neutral,
                  color: palette.textPrimary,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ),
          ],
        ),
      ],
      if (plan.isNotEmpty) ...[
        SureSectionHeader(label: l.spgPlanHeader),
        SurePanel.rows(margin: margin, children: plan),
      ],
      if (goal.notes?.trim().isNotEmpty ?? false) ...[
        SureSectionHeader(label: l.spgNotes),
        SurePanel(
          margin: margin,
          padding: const EdgeInsets.all(14),
          child: Text(
            goal.notes!.trim(),
            style: TextStyle(fontSize: 15, color: palette.textPrimary),
          ),
        ),
      ],
      const SizedBox(height: 16),
      _footerLinks(context),
      if (widget.lifecycleEnabled && goal.availableActions.isNotEmpty) ...[
        const SizedBox(height: 8),
        _actionsPanel(context),
      ],
      const SizedBox(height: 16),
      SureButtonPanel(
        key: const ValueKey('goalDelete'),
        label: l.spgDelete,
        destructive: true,
        busy: _deleting,
        margin: margin,
        onPressed: _delete,
      ),
    ];
  }

  Widget _amountRow(String title, String amount) {
    final palette = SureColors.of(context).palette;
    return SureListRow(
      title: title,
      trailing: MoneyText(
        amount,
        trend: MoneyTrend.neutral,
        color: palette.textSecondary,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w400),
      ),
    );
  }

  Widget _hero(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final goal = _goal;
    final target = goalsMoney(context, goal.targetAmount);
    final date = goal.targetDate;
    final sub = date == null || goal.isMaintained
        ? l.spgOfTarget(target)
        : l.spgOfTargetDue(target, SureDates.shortOf(context, date));
    final callout = goalCallout(context, goal);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        children: [
          GoalIcon(goal: goal, size: SureCategoryIcon.heroSize),
          const SizedBox(height: 10),
          Text(
            goal.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: SureTokens.weightSemibold,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          MoneyText(
            goalsMoney(context, goal.currentAmount),
            key: const ValueKey('goalHeroAmount'),
            trend: MoneyTrend.neutral,
            color: palette.textPrimary,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 32, height: 1.15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: SureMoney.tabular(
                TextStyle(fontSize: 13, color: palette.textSecondary)),
          ),
          const SizedBox(height: 12),
          GoalProgressBar(goal: goal),
          const SizedBox(height: 8),
          Text(
            '${goalStatusLabel(l, goal.displayStatus)} · ${goal.progressPercent}%',
            style: TextStyle(
              fontSize: 13,
              fontWeight: SureTokens.weightMedium,
              color: goalStatusColor(palette, goal.displayStatus),
            ),
          ),
          if (callout != null) ...[
            const SizedBox(height: 2),
            Text(
              callout,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pledgeRow(BuildContext context, GoalPledge pledge) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final amount = goalsMoney(context, pledge.amount);
    final expires = pledge.expiresAt;
    final expiry = expires == null
        ? null
        : SureDates.shortOf(context, expires.toLocal());
    final confirm =
        pledge.kind == 'manual_save' ? l.spgPledgeConfirmsManual : l.spgPledgeConfirmsTransfer;
    final busy = _busyPledgeId == pledge.id;

    return SureListRow(
      key: ValueKey('pledge-${pledge.id}'),
      title: pledge.accountName == null
          ? l.spgPledgeAmount(amount)
          : l.spgPledgeFromAccount(amount, pledge.accountName!),
      subtitle: expiry == null ? confirm : l.spgPledgeExpires(confirm, expiry),
      trailing: !widget.pledgesEnabled
          ? null
          : busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      key: ValueKey('pledgeExtend-${pledge.id}'),
                      onPressed: _busyPledgeId == null ? () => _renew(pledge) : null,
                      style: TextButton.styleFrom(
                        foregroundColor: palette.link,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: Text(l.spgPledgeExtend,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500)),
                    ),
                    IconButton(
                      key: ValueKey('pledgeCancel-${pledge.id}'),
                      tooltip: l.spgPledgeCancelConfirm,
                      visualDensity: VisualDensity.compact,
                      onPressed:
                          _busyPledgeId == null ? () => _cancelPledge(pledge) : null,
                      icon: SureIcon(SureIcons.x,
                          size: 18, color: palette.textSecondary),
                    ),
                  ],
                ),
    );
  }

  Widget _footerLinks(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final style = TextStyle(
      fontSize: 14,
      fontWeight: SureTokens.weightMedium,
      color: palette.link,
    );
    final edit = TextButton(
      key: const ValueKey('goalEdit'),
      onPressed: _deleting ? null : _edit,
      child: Text(l.spgEdit, style: style),
    );
    if (widget.lifecycleEnabled) return Center(child: edit);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        edit,
        Text('·', style: TextStyle(color: palette.textSubdued)),
        TextButton(
          key: const ValueKey('goalOpenWeb'),
          onPressed: _openWeb,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(l.spgLifecycleOnWeb, style: style)),
              const SizedBox(width: 2),
              SureIcon(SureIcons.arrowUpRight, size: 13, color: palette.link),
            ],
          ),
        ),
      ],
    );
  }
}
