# frozen_string_literal: true

class Api::V1::BudgetWritesController < Api::V1::BaseController
  include Api::V1::BudgetWriteAccess

  MONTH_FORMAT = /\A\d{4}-(0[1-9]|1[0-2])\z/

  wrap_parameters :budget, include: %w[budgeted_spending expected_income month]

  before_action -> { authorize_scope!(:read_write) }
  before_action :set_editable_budget, only: :update

  def self.local_prefixes
    [ controller_path, "api/v1/budgets" ]
  end
  private_class_method :local_prefixes

  # The API counterpart of opening a month on the web: the same
  # Budget.find_or_bootstrap, so the row it creates is the one the web page would.
  def create
    month = params.require(:budget).permit(:month)[:month].to_s
    return render_validation_error("month must look like 2026-12") unless month.match?(MONTH_FORMAT)

    start_date = Budget.param_to_date(Budget.date_to_param(Date.strptime(month, "%Y-%m")), family: current_resource_owner.family)
    unless Budget.budget_date_valid?(start_date, family: current_resource_owner.family)
      return render_validation_error("month is outside the range budgets can be set up for")
    end

    @budget = resolve_budget_for_month(start_date)
    render :show, status: @budget.previously_new_record? ? :created : :ok
  end

  def update
    attributes = budget_attributes
    return if performed?

    @budget.update!(attributes)
    Budget::RolloverCalculator.new(family: @budget.family, user: @budget.user).recompute!
    @budget.reload

    render :show
  end

  def copy_previous
    start_date = begin
      Budget.param_to_date(params[:id].to_s, family: current_resource_owner.family)
    rescue Date::Error
      raise ActiveRecord::RecordNotFound
    end

    @budget = resolve_budget_for_month(start_date)
    return render_budget_not_editable unless @budget.editable_by?(current_resource_owner)

    if @budget.initialized?
      return render_json({ error: "already_set_up", message: I18n.t("budgets.copy_previous.already_initialized") }, status: :conflict)
    end

    source_budget = @budget.most_recent_initialized_budget
    unless source_budget
      return render_json({ error: "no_source", message: I18n.t("budgets.copy_previous.no_source") }, status: :unprocessable_entity)
    end

    @budget.copy_from!(source_budget)
    @budget.reload

    render :show, status: :created
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
