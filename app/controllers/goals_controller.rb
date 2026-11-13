class GoalsController < ApplicationController
  before_action :require_preview_features!
  before_action :set_goal, only: %i[show edit update destroy pause resume complete archive unarchive reopen consume record_consumption]

  FUNDABLE_TYPES = Goal::FUNDABLE_ACCOUNT_TYPES
  rescue_from ActiveRecord::RecordNotFound, with: :goal_not_found

  STATE_FILTERS = %w[all active paused completed archived].freeze

  def index
    state_counts = Current.family.goals.group(:state).count
    @counts = STATE_FILTERS.each_with_object({}) do |state, h|
      h[state] = state == "all" ? state_counts.values.sum : (state_counts[state] || 0)
    end

    # Preloads + the family-wide backing-math injection (N+1 guard) live in
    # Goal.prepared_for, shared with the Plan hub's active_prepared_for.
    all_goals = Goal.prepared_for(Current.family)
    @active_goals = Goal.active_display_sort(all_goals.reject { |g| %w[completed archived].include?(g.state) })
    @completed_goals = all_goals.select { |g| g.state == "completed" }.sort_by { |g| g.name.downcase }
    @archived_goals = all_goals.select { |g| g.state == "archived" }
    # Completed goals join the chip-filterable grid below the active ones
    # so the `completed` chip can isolate them. Archived stays in a
    # separate collapsed-by-default section, opted out of the filter
    # entirely (rendered with filterable: false).
    @grid_goals = @active_goals + @completed_goals

    @linkable_account_count = Current.user.accessible_accounts.where(accountable_type: FUNDABLE_TYPES).visible.count
    @kpi = Goal::KpiSummary.new(Current.family, @active_goals).to_h
    @any_pending_pledge = @active_goals.any? { |g| g.open_pledges.any? }
    @show_search = @grid_goals.size > 6
    @breadcrumbs = plan_breadcrumb_prefix + [ [ t("goals.index.title"), nil ] ]
  end

  def show
    @open_pledges = @goal.open_pledges.reverse_chronological.to_a
    @unattributed_outflows = withdrawal_detector.unattributed_outflows.to_a
    @breadcrumbs = plan_breadcrumb_prefix + [
      [ t("goals.index.title"), goals_path ],
      [ @goal.name, nil ]
    ]
  end

  def new
    @goal = Current.family.goals.new(
      color: Goal::COLORS.sample,
      currency: Current.family.primary_currency_code
    )
    @linkable_accounts = linkable_accounts_for_new
    @currently_linked_account_ids = []
    @pooled_allocations = Goal.pooled_allocations_for(Current.family)
    @breadcrumbs = plan_breadcrumb_prefix + [
      [ t("goals.index.title"), goals_path ],
      [ t("goals.new.heading"), nil ]
    ]
  end

  def create
    @goal = Current.family.goals.new(goal_params)
    accounts = lookup_accounts(params.dig(:goal, :account_ids))
    # The family currency is what the form shows next to the target.
    @goal.currency = Current.family.primary_currency_code if @goal.currency.blank?

    allocations = submitted_allocations
    Goal.transaction do
      accounts.each { |a| @goal.goal_accounts.build(account: a, allocated_amount: allocations[a.id.to_s]) }
      @goal.save!
    end

    flash[:notice] = t(".success")
    respond_to do |format|
      format.html { redirect_to goal_path(@goal) }
      format.turbo_stream do
        render turbo_stream: turbo_stream.action(:redirect, goal_path(@goal))
      end
    end
  rescue ActiveRecord::RecordInvalid
    @linkable_accounts = linkable_accounts_for_new
    # From the in-memory links, not `pluck`: nothing is persisted on a failed
    # create, so a query would come back empty and every box the user ticked
    # would render unchecked. The amounts survived — the form reads those off
    # the same built records — so the user was left staring at an error telling
    # them to enter an amount, on a form whose accounts had silently cleared.
    @currently_linked_account_ids = @goal.goal_accounts.map { |ga| ga.account_id.to_s }
    @pooled_allocations = Goal.pooled_allocations_for(Current.family)
    render :new, status: :unprocessable_entity
  end

  def edit
    @linkable_accounts = linkable_accounts_for_new
    @pooled_allocations = Goal.pooled_allocations_for(Current.family)
    @currently_linked_account_ids = @goal.goal_accounts.pluck(:account_id).map(&:to_s)
  end

  def update
    account_ids = params.dig(:goal, :account_ids)
    accounts_supplied = !account_ids.nil?
    accounts = accounts_supplied ? lookup_accounts(account_ids) : []

    if accounts_supplied && accounts.empty?
      @goal.errors.add(:base, :at_least_one_linked_account_required)
      @linkable_accounts = linkable_accounts_for_new
      @pooled_allocations = Goal.pooled_allocations_for(Current.family)
      @currently_linked_account_ids = @goal.goal_accounts.pluck(:account_id).map(&:to_s)
      render :edit, status: :unprocessable_entity
      return
    end

    # Assign first, sync the links, then persist once. Saving the attributes
    # up front ran `must_have_at_least_one_linked_account` against the goal's
    # OLD links, so a goal orphaned by account deletion (Account has_many
    # :goal_accounts, dependent: :destroy) could never be edited back to
    # health: the save raised before the submitted accounts were attached.
    # One save over the fully-assembled goal validates what the user actually
    # submitted.
    Goal.transaction do
      @goal.assign_attributes(goal_update_params)
      if accounts_supplied
        sync_linked_accounts!(@goal, accounts, submitted_allocations)
      else
        @goal.save!
      end
    end

    flash[:notice] = t(".success")
    respond_to do |format|
      format.html { redirect_to goal_path(@goal) }
      format.turbo_stream do
        render turbo_stream: turbo_stream.action(:redirect, goal_path(@goal))
      end
    end
  rescue ActiveRecord::RecordInvalid
    @linkable_accounts = linkable_accounts_for_new
    @pooled_allocations = Goal.pooled_allocations_for(Current.family)
    @currently_linked_account_ids = @goal.goal_accounts.pluck(:account_id).map(&:to_s)
    render :edit, status: :unprocessable_entity
  end

  # Deletable from any state. Destroying a goal cascades only to its own
  # goal_accounts / goal_pledges — and GoalPledge#clear_matched_transaction_extra
  # unstamps the pledge id it wrote onto a matched transaction. No account,
  # balance, entry or transaction is removed, so the archive-first gate this
  # used to enforce bought no safety; it only hid the action behind a two-step
  # flow no other Sure resource requires.
  def destroy
    @goal.destroy!
    redirect_to goals_path, notice: t(".success")
  end

  def pause
    perform_transition!(:pause)
  end

  def resume
    perform_transition!(:resume)
  end

  def complete
    perform_transition!(:complete)
  end

  def archive
    perform_transition!(:archive)
  end

  def unarchive
    perform_transition!(:unarchive)
  end

  # Renders the dialog. The write lives in its own action below.
  def consume
    @consumption_accounts = eligible_consumption_accounts
  end

  def record_consumption
    amount = goal_consumption.record!(
      amount: params[:amount], account_id: params[:account_id], transaction_id: params[:transaction_id]
    )
    redirect_to goal_path(@goal),
                notice: t("goals.consume.success", amount: Money.new(amount, @goal.currency).format)
  rescue Goal::ConsumptionRefused => e
    redirect_to goal_path(@goal), alert: t("goals.consume.errors.#{e.reason}")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to goal_path(@goal), alert: e.record.errors.full_messages.to_sentence
  end

  def reopen
    perform_transition!(:reopen)
  end

  helper_method :eligible_consumption_accounts

  private
    def set_goal
      @goal = Current.family.goals
                             .includes(:open_pledges, linked_accounts: :account_providers)
                             .find(params[:id])
    end

    def goal_not_found
      redirect_to goals_path, alert: t("goals.errors.not_found")
    end

    def goal_params
      params.require(:goal).permit(:name, :target_amount, :target_date, :color, :icon, :notes, :kind, :target_mode, :target_months)
    end

    def goal_update_params
      params.require(:goal).permit(:name, :target_amount, :target_date, :color, :icon, :notes, :kind, :target_mode, :target_months)
    end

    def lookup_accounts(ids)
      return [] if ids.blank?

      ids = Array(ids).reject(&:blank?)
      Current.user.accessible_accounts.where(accountable_type: FUNDABLE_TYPES).visible.where(id: ids).to_a
    end

    def linkable_accounts_for_new
      Current.user.accessible_accounts.where(accountable_type: FUNDABLE_TYPES).visible.alphabetically.to_a
    end

    def sync_linked_accounts!(goal, accounts, allocations = {})
      desired_ids = accounts.map(&:id).to_set
      current_ids = goal.goal_accounts.pluck(:account_id).to_set

      # Only unlink accounts the current user can actually see in the picker.
      # A family goal may be linked to another member's private account, which
      # never renders as a checkbox — so its absence from the submitted set is
      # not an intentional removal and must not destroy the link.
      removable_ids = Current.user.accessible_accounts.where(id: current_ids.to_a).pluck(:id).to_set

      ((current_ids & removable_ids) - desired_ids).each do |id|
        goal.goal_accounts.where(account_id: id).destroy_all
      end
      goal.goal_accounts.reload

      # Add new links and refresh the earmark on kept links. Only touch the
      # allocation when the form actually submitted a value for that account
      # (allocations.key?), so a caller that omits the hash leaves earmarks
      # untouched. Save through the goal so currency / depository / family
      # validations fire — create! on goal_accounts bypasses them.
      accounts.each do |account|
        existing = goal.goal_accounts.find { |ga| ga.account_id == account.id }
        if existing
          existing.allocated_amount = allocations[account.id.to_s] if allocations.key?(account.id.to_s)
        else
          goal.goal_accounts.build(account: account, allocated_amount: allocations[account.id.to_s])
        end
      end
      goal.save!
    end

    # { account_id_string => amount_string_or_nil } from goal[allocations].
    # A blank amount means "dedicate the whole balance" (NULL allocated_amount).
    def submitted_allocations
      raw = params.dig(:goal, :allocations)
      return {} if raw.blank?

      hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
      hash.each_with_object({}) do |(account_id, amount), memo|
        memo[account_id.to_s] = amount.to_s.strip.presence
      end
    end

    def goal_consumption
      @goal_consumption ||= Goal::Consumption.new(@goal, user: Current.user)
    end

    def eligible_consumption_accounts
      goal_consumption.eligible_accounts
    end

    def withdrawal_detector
      goal_consumption.withdrawal_detector
    end

    def perform_transition!(event)
      unless @goal.aasm.may_fire_event?(event)
        redirect_to goal_path(@goal), alert: t(".invalid_transition")
        return
      end

      # AASM's bang event returns false — it does NOT raise — when the save
      # that persists the new state fails validation. The return value used to
      # be discarded, so an invalid goal (e.g. orphaned by account deletion)
      # flashed "Goal archived." while the state never moved. Surface the
      # validation error instead of claiming success.
      unless @goal.public_send("#{event}!")
        redirect_to goal_path(@goal),
                    alert: @goal.errors.full_messages.to_sentence.presence || t(".invalid_transition")
        return
      end

      respond_to do |format|
        format.html { redirect_to goal_path(@goal), notice: t(".success") }
        format.turbo_stream do
          render turbo_stream: turbo_stream.action(:redirect, goal_path(@goal))
        end
      end
    end
end
