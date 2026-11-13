import '../utils/json_parsing.dart';

/// A server money field: the formatted string (`"$3,100.00"`) plus its minor
/// units (`310000`), as the Sure+ goals API sends them (`<name>` and
/// `<name>_cents`).
class GoalMoney {
  const GoalMoney(this.formatted, this.cents);

  final String formatted;
  final int? cents;

  /// Null when the server sent no formatted value.
  static GoalMoney? fromJson(Map<String, dynamic> json, String name) {
    final formatted = JsonParsing.parseString(json[name]);
    if (formatted == null || formatted.isEmpty) return null;
    return GoalMoney(formatted, JsonParsing.parseInt(json['${name}_cents']));
  }

  bool get isPositive => (cents ?? 0) > 0;
}

/// An open "I just saved toward this" pledge on a goal
/// (`app/views/api/v1/goals/_pledge.json.jbuilder`).
class GoalPledge {
  const GoalPledge({
    required this.id,
    required this.accountId,
    this.accountName,
    required this.kind,
    required this.status,
    required this.amount,
    this.daysLeft,
    this.expiresAt,
  });

  final String id;
  final String accountId;

  /// Null when the caller cannot see the account.
  final String? accountName;

  /// `transfer` or `manual_save`.
  final String kind;

  /// `open`, `matched`, `cancelled` or `expired`.
  final String status;
  final GoalMoney amount;
  final int? daysLeft;
  final DateTime? expiresAt;

  factory GoalPledge.fromJson(Map<String, dynamic> json) => GoalPledge(
        id: json['id']?.toString() ?? '',
        accountId: json['account_id']?.toString() ?? '',
        accountName: JsonParsing.parseString(json['account_name']),
        kind: json['kind']?.toString() ?? 'transfer',
        status: json['status']?.toString() ?? 'open',
        amount: GoalMoney.fromJson(json, 'amount') ?? const GoalMoney('', null),
        daysLeft: JsonParsing.parseInt(json['days_left']),
        expiresAt: JsonParsing.parseDateTime(json['expires_at']),
      );
}

/// An account funding a goal (`linked_accounts[]`).
class GoalLinkedAccount {
  const GoalLinkedAccount({
    required this.id,
    required this.name,
    this.accountableType,
    required this.currency,
    this.wholeAccount = true,
    this.allocatedAmount,
    this.backingAmount,
  });

  final String id;
  final String name;
  final String? accountableType;
  final String currency;

  /// True when the goal claims the account's whole balance (no earmark).
  final bool wholeAccount;

  /// The earmark, in the account's currency, when not [wholeAccount].
  final GoalMoney? allocatedAmount;

  /// What this account currently contributes to the goal.
  final GoalMoney? backingAmount;

  factory GoalLinkedAccount.fromJson(Map<String, dynamic> json) =>
      GoalLinkedAccount(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        accountableType: JsonParsing.parseString(json['accountable_type']),
        currency: json['currency']?.toString() ?? '',
        wholeAccount: json['whole_account'] != false,
        allocatedAmount: GoalMoney.fromJson(json, 'allocated_amount'),
        backingAmount: GoalMoney.fromJson(json, 'backing_amount'),
      );
}

/// A savings goal from the Sure+ API (`GET /api/v1/goals`, feature `goals`),
/// as `app/views/api/v1/goals/_goal.json.jbuilder` renders it.
class Goal {
  const Goal({
    required this.id,
    required this.name,
    this.kind = 'one_off',
    this.targetMode = 'fixed',
    this.targetMonths,
    required this.state,
    required this.status,
    required this.displayStatus,
    this.color,
    this.icon,
    this.notes,
    required this.currency,
    this.targetDate,
    this.daysLeft,
    this.monthsRemaining,
    this.targetAmount,
    this.currentAmount,
    this.remainingAmount,
    this.monthlyTargetAmount,
    this.pace,
    this.catchUpAmount,
    this.progressPercent = 0,
    this.projectedCompletionDate,
    this.behindPace = false,
    this.statusCallout,
    this.pendingPledgesCount = 0,
    this.openPledges = const [],
    this.linkedAccounts = const [],
    this.availableActions = const [],
  });

  static const states = ['active', 'paused', 'completed', 'archived'];

  final String id;
  final String name;

  /// `one_off` or `maintained` (a reserve).
  final String kind;

  /// `fixed` or `months_of_expenses`.
  final String targetMode;
  final int? targetMonths;

  /// Lifecycle: `active`, `paused`, `completed` or `archived`.
  final String state;

  /// `reached`, `on_track`, `behind`, `no_target_date`, `funded`, `depleted`.
  final String status;

  /// [status], or the lifecycle [state] when paused, completed or archived.
  final String displayStatus;

  /// `#rrggbb`.
  final String? color;

  /// A Lucide icon name (`Category.icon_codes`).
  final String? icon;
  final String? notes;
  final String currency;
  final DateTime? targetDate;
  final int? daysLeft;
  final double? monthsRemaining;
  final GoalMoney? targetAmount;
  final GoalMoney? currentAmount;
  final GoalMoney? remainingAmount;
  final GoalMoney? monthlyTargetAmount;
  final GoalMoney? pace;
  final GoalMoney? catchUpAmount;
  final int progressPercent;
  final DateTime? projectedCompletionDate;
  final bool behindPace;

  /// The web's localized one-line status, or null.
  final String? statusCallout;
  final int pendingPledgesCount;
  final List<GoalPledge> openPledges;
  final List<GoalLinkedAccount> linkedAccounts;

  /// What this viewer may do next (feature `goals.lifecycle`): the permitted
  /// state-machine events (`pause`, `resume`, `complete`, `archive`,
  /// `unarchive`, `reopen`) plus `consume` when there is something to spend.
  final List<String> availableActions;

  bool get isMaintained => kind == 'maintained';

  factory Goal.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) parse) {
      final raw = json[key];
      if (raw is! List) return const [];
      return [
        for (final item in raw)
          if (item is Map<String, dynamic>) parse(item),
      ];
    }

    final state = json['state']?.toString() ?? 'active';
    final status = json['status']?.toString() ?? '';
    final months = json['months_remaining'];
    final percent = json['progress_percent'];
    return Goal(
      id: JsonParsing.parseRequiredString(json['id'], 'goal id'),
      name: json['name']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'one_off',
      targetMode: json['target_mode']?.toString() ?? 'fixed',
      targetMonths: JsonParsing.parseInt(json['target_months']),
      state: state,
      status: status,
      displayStatus: JsonParsing.parseString(json['display_status']) ??
          (state == 'active' ? status : state),
      color: JsonParsing.parseString(json['color']),
      icon: JsonParsing.parseString(json['icon']),
      notes: JsonParsing.parseString(json['notes']),
      currency: json['currency']?.toString() ?? '',
      targetDate: JsonParsing.parseDateTime(json['target_date']),
      daysLeft: JsonParsing.parseInt(json['days_left']),
      monthsRemaining: months is num ? months.toDouble() : null,
      targetAmount: GoalMoney.fromJson(json, 'target_amount'),
      currentAmount: GoalMoney.fromJson(json, 'current_amount'),
      remainingAmount: GoalMoney.fromJson(json, 'remaining_amount'),
      monthlyTargetAmount: GoalMoney.fromJson(json, 'monthly_target_amount'),
      pace: GoalMoney.fromJson(json, 'pace'),
      catchUpAmount: GoalMoney.fromJson(json, 'catch_up_amount'),
      progressPercent: percent is num ? percent.round() : 0,
      projectedCompletionDate:
          JsonParsing.parseDateTime(json['projected_completion_date']),
      behindPace: json['behind_pace'] == true,
      statusCallout: JsonParsing.parseString(json['status_callout']),
      pendingPledgesCount:
          JsonParsing.parseInt(json['pending_pledges_count']) ?? 0,
      openPledges: list('open_pledges', GoalPledge.fromJson),
      linkedAccounts: list('linked_accounts', GoalLinkedAccount.fromJson),
      availableActions: [
        if (json['available_actions'] case final List actions)
          for (final action in actions)
            if (action is String) action,
      ],
    );
  }
}

/// The Goals list header figures (`GET /api/v1/goals/summary`, feature
/// `goals.summary`), as `app/views/api/v1/goals/summary.json.jbuilder`
/// renders them: the web's KPI strip plus the Plan hub's saved / target.
class GoalsSummary {
  const GoalsSummary({
    this.velocity30d,
    this.velocityPrior30d,
    this.needsThisMonth,
    this.onTrackCount = 0,
    this.trackedTotal = 0,
    this.reachedCount = 0,
    this.behindCount = 0,
    this.saved,
    this.target,
  });

  /// Contributed in the last 30 days, signed ("-$110.00").
  final GoalMoney? velocity30d;
  final GoalMoney? velocityPrior30d;
  final GoalMoney? needsThisMonth;
  final int onTrackCount;
  final int trackedTotal;
  final int reachedCount;
  final int behindCount;

  /// Only goals in the family currency, as on the web.
  final GoalMoney? saved;
  final GoalMoney? target;

  factory GoalsSummary.fromJson(Map<String, dynamic> json) => GoalsSummary(
        velocity30d: GoalMoney.fromJson(json, 'velocity_30d'),
        velocityPrior30d: GoalMoney.fromJson(json, 'velocity_prior_30d'),
        needsThisMonth: GoalMoney.fromJson(json, 'needs_this_month'),
        onTrackCount: JsonParsing.parseInt(json['on_track_count']) ?? 0,
        trackedTotal: JsonParsing.parseInt(json['tracked_total']) ?? 0,
        reachedCount: JsonParsing.parseInt(json['reached_count']) ?? 0,
        behindCount: JsonParsing.parseInt(json['behind_count']) ?? 0,
        saved: GoalMoney.fromJson(json, 'saved'),
        target: GoalMoney.fromJson(json, 'target'),
      );
}
