# The KPI strip on the goals index, over the family's active (not completed
# or archived) prepared goals. Shared by the web index and the API summary.
class Goal::KpiSummary
  def initialize(family, active_goals)
    @family = family
    @active_goals = active_goals
  end

  def to_h
    active_goals = @active_goals
    family = @family
    currency = family.primary_currency_code
    today = Date.current

    windows = family.savings_inflow_windows(window_days: 30, now: today)
    velocity_30d = windows[:current]
    velocity_prior_30d = windows[:prior]
    delta_amount = velocity_30d - velocity_prior_30d
    delta_percent = velocity_prior_30d.zero? ? nil : ((delta_amount / velocity_prior_30d.abs) * 100).round(1)

    # Sign decoupling: the headline-amount sign reflects this month's
    # direction ("−$200 last 30d" = net outflow); the delta direction
    # (↑/↓ vs prior 30d) goes on the subline. Conflating them produced the
    # "−$1234" + "↓ 27%" tile where the minus looked like a loss but the
    # $1234 was actually the (positive) amount contributed.
    headline_sign = velocity_30d.negative? ? "−" : ""
    delta_direction = if delta_amount.positive? then :up
    elsif delta_amount.negative? then :down
    else :flat
    end

    # behind_pace? excludes paused goals — pausing stops the pace clock,
    # so a paused-but-behind goal belongs in the paused count (below),
    # not in "N behind" or the "needs this month" sum. Keeps this tile
    # consistent with the Plan hub's summary (Goal.summary_for).
    needs = active_goals
      .select(&:behind_pace?)
      .sum { |g| g.monthly_target_amount.to_d }
    behind = active_goals.count(&:behind_pace?)
    # Paused goals are excluded from the on-track numerator for the same
    # reason they're excluded from tracked_total below — otherwise the
    # "X of Y" fraction could exceed its own denominator.
    on_track = active_goals.count { |g| !g.paused? && g.status == :on_track }
    reached = active_goals.count { |g| g.status == :reached }
    no_date = active_goals.count { |g| g.status == :no_target_date }
    paused = active_goals.count(&:paused?)

    # Denominator of the "Goals on track" tile. A goal only belongs in
    # the fraction if there is a benchmark to compare against:
    # - reached  → target already hit, no longer tracked toward pace
    # - paused   → user stopped the pace clock on purpose
    # - no_target_date → open-ended saving (emergency fund, sabbatical
    #   fund, etc.) has no required monthly pace, so "on track" is
    #   undefined. Counting it would penalise the user for having
    #   open-ended goals — they'd never improve the ratio.
    # - maintained → a reserve has no deadline and no pace benchmark at
    #   all. Its statuses are `funded`/`depleted`, which match none of the
    #   exclusions above, so without this it would land in the denominator
    #   and never in the numerator: a family with one reserve read
    #   "0 of 1 on track" for a goal that is working exactly as intended.
    # When this hits zero the tile swaps to a celebration / empty
    # state in the view.
    tracked_total = active_goals.count do |g|
      !g.paused? && !g.maintained? && g.status != :reached && g.status != :no_target_date
    end

    {
      currency: currency,
      velocity_30d_money: Money.new(velocity_30d.abs, currency),
      velocity_prior_30d_money: Money.new(velocity_prior_30d.abs, currency),
      velocity_30d_signed_money: Money.new(velocity_30d, currency),
      velocity_prior_30d_signed_money: Money.new(velocity_prior_30d, currency),
      velocity_30d_sign: headline_sign,
      velocity_delta_percent: delta_percent,
      velocity_direction: delta_direction,
      needs_this_month_money: Money.new(needs, currency),
      on_track_count: on_track,
      reached_count: reached,
      behind_count: behind,
      no_date_count: no_date,
      paused_count: paused,
      tracked_total: tracked_total,
      active_total: active_goals.size
    }
  end
end
