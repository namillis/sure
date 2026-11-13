# frozen_string_literal: true

module Api::V1::BudgetWriteAccess
  extend ActiveSupport::Concern

  private

    def visible_owner_ids
      shared_with_me = BudgetShare.where(viewer_id: current_resource_owner.id).pluck(:owner_id)
      [ nil, current_resource_owner.id, *shared_with_me ]
    end

    # `owner` follows the web's BudgetOwnership: absent or the caller's own id is
    # the caller's budget, "household" the shared one, and another member's id
    # their budget if they shared it. Like the web, a month is only created for
    # the caller or the household, never on another member's behalf. Where the
    # web falls back to the caller's own budget, this answers 404 instead.
    def resolve_budget_for_month(start_date)
      family = current_resource_owner.family
      owner_id = params[:owner].presence

      if owner_id.nil? || owner_id == "household" || owner_id == current_resource_owner.id
        budget = Budget.find_or_bootstrap(family, start_date: start_date, user: current_resource_owner, household: owner_id == "household")
      elsif visible_owner_ids.include?(owner_id)
        budget_start, budget_end = Budget.period_for(start_date, family: family)
        budget = family.budgets.find_by(start_date: budget_start, end_date: budget_end, user_id: owner_id)
      end

      budget || raise(ActiveRecord::RecordNotFound)
    end

    def render_budget_not_editable
      render_json({ error: "forbidden", message: "This budget is shared with you read-only" }, status: :forbidden)
    end

    def parse_non_negative_amount(value)
      return unless value.is_a?(Numeric) || (value.is_a?(String) && value.strip.match?(/\A\d+(\.\d+)?\z/))

      amount = BigDecimal(value.to_s.strip)
      amount if amount.finite? && amount >= 0
    rescue ArgumentError
      nil
    end
end
