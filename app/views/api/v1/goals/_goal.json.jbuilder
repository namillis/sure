# frozen_string_literal: true

money_to_minor_units = lambda do |money|
  (money.amount * money.currency.minor_unit_conversion).round(0).to_i if money
end
money_field = lambda do |name, money|
  json.set! name, money&.format
  json.set! "#{name}_cents", money_to_minor_units.call(money)
end
currency = goal.currency
monthly_target = goal.monthly_target_amount

json.id goal.id
json.name goal.name
json.kind goal.kind
json.target_mode goal.target_mode
json.target_months goal.target_months
json.state goal.state
json.status goal.status.to_s
json.display_status goal.display_status.to_s
json.color goal.color
json.icon goal.icon
json.notes goal.notes
json.currency currency
json.target_date goal.target_date
json.days_left(goal.target_date && (goal.target_date - Date.current).to_i)
json.months_remaining goal.months_remaining&.round(2)
money_field.call(:target_amount, goal.target_amount_money)
money_field.call(:current_amount, goal.current_balance_money)
money_field.call(:progress_amount, goal.progress_amount_money)
money_field.call(:consumed_amount, goal.consumed_amount_money)
money_field.call(:remaining_amount, goal.remaining_amount_money)
money_field.call(:monthly_target_amount, monthly_target && Money.new(monthly_target, currency))
money_field.call(:pace, goal.pace_money)
money_field.call(:catch_up_amount, goal.catch_up_delta_money)
money_field.call(:projection_end_amount, Money.new(goal.projection_end_amount, currency))
money_field.call(:market_value, goal.market_value_money)
json.progress_percent goal.progress_percent
json.progress_basis goal.progress_basis
json.months_of_runway goal.months_of_runway&.to_f
json.projected_completion_date(
  if goal.one_off? && !goal.completed? && goal.target_date && goal.pace.to_d.positive? && goal.remaining_amount.to_d.positive?
    Date.current >> (goal.remaining_amount.to_d / goal.pace.to_d).ceil.to_i
  end
)
json.behind_pace goal.behind_pace?
json.needs_attention goal.needs_attention?
json.status_callout goal.status_callout_context
json.currency_conversion_incomplete goal.currency_conversion_incomplete?
json.last_matched_pledge_date goal.last_matched_pledge_at
json.pledges_use_transfer goal.pledges_use_transfer?
json.pending_pledges_count goal.open_pledges.size
json.open_pledges goal.open_pledges.sort_by(&:created_at).reverse do |pledge|
  json.partial! "api/v1/goals/pledge", pledge: pledge, accessible_account_ids: accessible_account_ids
end
json.linked_account_count goal.linked_accounts.size
goal_accounts_by_account_id = goal.goal_accounts.index_by(&:account_id)
json.linked_accounts goal.linked_accounts.select { |account| accessible_account_ids.include?(account.id) }.sort_by { |account| account.name.downcase } do |account|
  link = goal_accounts_by_account_id[account.id]
  json.id account.id
  json.name account.name
  json.accountable_type account.accountable_type
  json.currency account.currency
  json.whole_account link.nil? || link.whole_account?
  money_field.call(:allocated_amount, link&.allocated_amount && Money.new(link.allocated_amount, account.currency))
  money_field.call(:backing_amount, goal.account_backing(account))
end
json.completed_at goal.completed_at
json.created_at goal.created_at
json.updated_at goal.updated_at
