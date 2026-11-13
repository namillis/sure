# frozen_string_literal: true

class Api::V1::BudgetWritesController < Api::V1::BaseController
  include Api::V1::BudgetWriteAccess

  wrap_parameters :budget, include: %w[budgeted_spending expected_income]

  before_action -> { authorize_scope!(:read_write) }
  before_action :set_editable_budget

  def self.local_prefixes
    [ controller_path, "api/v1/budgets" ]
  end
  private_class_method :local_prefixes

  def update
    attributes = budget_attributes
    return if performed?

    @budget.update!(attributes)
    Budget::RolloverCalculator.new(family: @budget.family, user: @budget.user).recompute!
    @budget.reload

    render :show
  end

  private

    def set_editable_budget
      raise ActiveRecord::RecordNotFound unless valid_uuid?(params[:id])

      @budget = current_resource_owner.family.budgets.where(user_id: visible_owner_ids).find(params[:id])
      render_budget_not_editable unless @budget.editable_by?(current_resource_owner)
    end

    def budget_attributes
      permitted = params.require(:budget).permit(:budgeted_spending, :expected_income)
      return render_validation_error("budgeted_spending or expected_income is required") if permitted.empty?

      permitted.to_h.each_with_object({}) do |(field, value), attributes|
        amount = parse_non_negative_amount(value)
        return render_validation_error("#{field} must be a number greater than or equal to 0") if amount.nil?

        attributes[field] = amount
      end
    end
end
