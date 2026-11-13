# frozen_string_literal: true

class Api::V1::GoalsController < Api::V1::BaseController
  STATE_FILTERS = %w[active paused completed archived].freeze

  before_action :ensure_read_scope, only: %i[index show]
  before_action :ensure_write_scope, only: %i[create update destroy]
  before_action :require_preview_features_for_api
  before_action :set_goal, only: %i[show update destroy]

  def index
    family = current_resource_owner.family
    return render_validation_error("state must be one of: #{STATE_FILTERS.join(', ')}") if params[:state].present? && !params[:state].in?(STATE_FILTERS)

    scope = params[:state].present? ? family.goals.where(state: params[:state]) : family.goals
    goals = Goal.prepared_for(family, scope: scope)
    active = Goal.active_display_sort(goals.reject { |g| %w[completed archived].include?(g.state) })
    completed = goals.select { |g| g.state == "completed" }.sort_by { |g| g.name.downcase }
    archived = goals.select { |g| g.state == "archived" }
    @goals = active + completed + archived
    @accessible_account_ids = accessible_account_ids_for(@goals)

    render :index
  end

  def show
    @accessible_account_ids = accessible_account_ids_for([ @goal ])
    render :show
  end

  def create
    family = current_resource_owner.family
    @goal = family.goals.new(goal_params)
    @goal.currency = family.primary_currency_code if @goal.currency.blank?
    @goal.color ||= Goal::COLORS.sample

    accounts = lookup_accounts(goal_input[:account_ids])
    allocations = submitted_allocations
    Goal.transaction do
      accounts.each { |a| @goal.goal_accounts.build(account: a, allocated_amount: allocations[a.id.to_s]) }
      @goal.save!
    end

    render_goal(status: :created)
  rescue ActiveRecord::RecordInvalid
    render_goal_errors("Goal could not be created")
  end

  def update
    account_ids = goal_input[:account_ids]
    accounts_supplied = !account_ids.nil?
    accounts = accounts_supplied ? lookup_accounts(account_ids) : []

    if accounts_supplied && accounts.empty?
      @goal.errors.add(:base, :at_least_one_linked_account_required)
      return render_goal_errors("Goal could not be updated")
    end

    Goal.transaction do
      @goal.assign_attributes(goal_params)
      if accounts_supplied
        sync_linked_accounts!(@goal, accounts, submitted_allocations)
      else
        @goal.save!
      end
    end

    render_goal
  rescue ActiveRecord::RecordInvalid
    render_goal_errors("Goal could not be updated")
  end

  def destroy
    @goal.destroy!

    render json: { message: "Goal deleted successfully" }, status: :ok
  end

  private
    def ensure_write_scope
      authorize_scope!(:write)
    end

    def require_preview_features_for_api
      return if current_resource_owner.preview_features_enabled?

      render_json(
        { error: "feature_disabled", message: "Preview features are not enabled for this user" },
        status: :forbidden
      )
    end

    def set_goal
      raise ActiveRecord::RecordNotFound unless valid_uuid?(params[:id])

      family = current_resource_owner.family
      @goal = Goal.prepared_for(family, scope: family.goals.where(id: params[:id])).first ||
        raise(ActiveRecord::RecordNotFound)
    end

    def render_goal(status: :ok)
      family = current_resource_owner.family
      @goal = Goal.prepared_for(family, scope: family.goals.where(id: @goal.id)).first
      @accessible_account_ids = accessible_account_ids_for([ @goal ])
      render :show, status: status
    end

    def render_goal_errors(message)
      render json: {
        error: "validation_failed",
        message: message,
        errors: @goal.errors.full_messages
      }, status: :unprocessable_entity
    end

    def goal_input
      params.require(:goal)
    end

    def goal_params
      goal_input.permit(:name, :target_amount, :target_date, :color, :icon, :notes, :kind, :target_mode, :target_months)
    end

    def fundable_accessible_accounts
      current_resource_owner.accessible_accounts.where(accountable_type: Goal::FUNDABLE_ACCOUNT_TYPES).visible
    end

    def lookup_accounts(ids)
      return [] if ids.blank?

      ids = Array(ids).map(&:to_s).reject(&:blank?).select { |id| valid_uuid?(id) }
      fundable_accessible_accounts.where(id: ids).to_a
    end

    def accessible_account_ids_for(goals)
      linked_ids = goals.flat_map { |goal| goal.linked_accounts.map(&:id) }.uniq
      current_resource_owner.accessible_accounts.where(id: linked_ids).pluck(:id).to_set
    end

    # Same rules as GoalsController#sync_linked_accounts!: links to accounts the
    # caller cannot see are never removed, and an earmark only changes when one
    # was submitted for that account.
    def sync_linked_accounts!(goal, accounts, allocations)
      desired_ids = accounts.map(&:id).to_set
      current_ids = goal.goal_accounts.pluck(:account_id).to_set
      removable_ids = current_resource_owner.accessible_accounts.where(id: current_ids.to_a).pluck(:id).to_set

      ((current_ids & removable_ids) - desired_ids).each do |id|
        goal.goal_accounts.where(account_id: id).destroy_all
      end
      goal.goal_accounts.reload

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

    # { account_id => amount_or_nil } from goal[allocations]; a blank amount
    # means the goal claims the account's whole balance.
    def submitted_allocations
      raw = goal_input[:allocations]
      return {} if raw.blank?

      hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
      hash.each_with_object({}) do |(account_id, amount), memo|
        memo[account_id.to_s] = amount.to_s.strip.presence
      end
    end
end
