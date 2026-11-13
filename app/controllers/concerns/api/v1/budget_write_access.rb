# frozen_string_literal: true

module Api::V1::BudgetWriteAccess
  extend ActiveSupport::Concern

  private

    def visible_owner_ids
      shared_with_me = BudgetShare.where(viewer_id: current_resource_owner.id).pluck(:owner_id)
      [ nil, current_resource_owner.id, *shared_with_me ]
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
