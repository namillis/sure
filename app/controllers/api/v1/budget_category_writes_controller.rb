# frozen_string_literal: true

class Api::V1::BudgetCategoryWritesController < Api::V1::BaseController
  include Api::V1::BudgetWriteAccess

  wrap_parameters :budget_category, include: %w[budgeted_spending rollover_enabled]

  before_action -> { authorize_scope!(:read_write) }
  before_action :set_editable_budget_category, only: :update

  def self.local_prefixes
    [ controller_path, "api/v1/budget_categories" ]
  end
  private_class_method :local_prefixes

  def update
    changes = budget_category_changes
    return if performed?

    @budget_category.update!(rollover_enabled: changes[:rollover_enabled]) if changes.key?(:rollover_enabled)
    @budget_category.propagate_rollover_choice_forward! if changes.key?(:rollover_enabled)
    @budget_category.update_budgeted_spending!(changes[:budgeted_spending]) if changes.key?(:budgeted_spending)

    budget = @budget_category.budget
    Budget::RolloverCalculator.new(family: budget.family, user: budget.user).recompute!
    @budget_category.reload

    render :show
  rescue ActiveRecord::RecordInvalid => e
    render_validation_error(e.record.errors.full_messages.to_sentence)
  end

  # Mirrors the web's BudgetCategoriesController#move, including running the
  # recompute only after move_allocation! has committed.
  def move
    @budget = current_resource_owner.family.budgets.where(user_id: visible_owner_ids).find(uuid_param!(params[:budget_id]))
    return render_budget_not_editable unless @budget.editable_by?(current_resource_owner)

    move_params = params.require(:move).permit(:from_id, :to_id, :amount)
    amount = parse_non_negative_amount(move_params[:amount])
    return render_validation_error("amount must be a number greater than 0") if amount.nil?

    from = visible_budget_categories.find(uuid_param!(move_params[:from_id]))
    to = visible_budget_categories.find(uuid_param!(move_params[:to_id]))
    raise BudgetCategory::InvalidMove.new(:different_budgets) unless [ from, to ].all? { |bc| bc.budget_id == @budget.id }

    @from, @to = BudgetCategory.move_allocation!(from: from, to: to, amount: amount)
    Budget::RolloverCalculator.new(family: @budget.family, user: @budget.user).recompute!
    [ @budget, @from, @to ].each(&:reload)

    render :move
  rescue BudgetCategory::InvalidMove => e
    render_json({ error: "validation_failed", message: e.message, errors: [ e.message ], reason: e.reason.to_s },
                status: :unprocessable_entity)
  end

  private

    def uuid_param!(value)
      raise ActiveRecord::RecordNotFound unless valid_uuid?(value)

      value
    end

    def visible_budget_categories
      BudgetCategory
        .joins(:budget)
        .where(budgets: { family_id: current_resource_owner.family_id, user_id: visible_owner_ids })
    end

    def set_editable_budget_category
      @budget_category = visible_budget_categories
        .includes({ budget: { budget_categories: { category: :parent } } }, category: :parent)
        .find(uuid_param!(params[:id]))
      render_budget_not_editable unless @budget_category.budget.editable_by?(current_resource_owner)
    end

    def budget_category_changes
      permitted = params.require(:budget_category).permit(:budgeted_spending, :rollover_enabled)
      return render_validation_error("budgeted_spending or rollover_enabled is required") if permitted.empty?

      changes = {}

      if permitted.key?(:rollover_enabled)
        rollover_enabled = parse_boolean(permitted[:rollover_enabled])
        return render_validation_error("rollover_enabled must be true or false") if rollover_enabled.nil?

        changes[:rollover_enabled] = rollover_enabled
      end

      if permitted.key?(:budgeted_spending)
        budgeted_spending = permitted[:budgeted_spending].presence || 0
        amount = parse_non_negative_amount(budgeted_spending)
        return render_validation_error("budgeted_spending must be a number greater than or equal to 0") if amount.nil?

        changes[:budgeted_spending] = amount
      end

      changes
    end

    def parse_boolean(value)
      case value
      when true, "true", "1", 1 then true
      when false, "false", "0", 0 then false
      end
    end
end
