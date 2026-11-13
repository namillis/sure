# frozen_string_literal: true

money_field = lambda do |name, money|
  json.set! name, money.format
  json.set! "#{name}_cents", (money.amount * money.currency.minor_unit_conversion).round(0).to_i
end

json.currency @kpi[:currency]
money_field.call(:velocity_30d, @kpi[:velocity_30d_signed_money])
money_field.call(:velocity_prior_30d, @kpi[:velocity_prior_30d_signed_money])
json.velocity_delta_percent @kpi[:velocity_delta_percent]&.to_f
json.velocity_direction @kpi[:velocity_direction].to_s
money_field.call(:needs_this_month, @kpi[:needs_this_month_money])
json.on_track_count @kpi[:on_track_count]
json.tracked_total @kpi[:tracked_total]
json.reached_count @kpi[:reached_count]
json.behind_count @kpi[:behind_count]
json.no_date_count @kpi[:no_date_count]
json.paused_count @kpi[:paused_count]
json.active_total @kpi[:active_total]
money_field.call(:saved, @totals[:saved_money])
money_field.call(:target, @totals[:target_money])
json.pending_pledges_count @totals[:pending_count]
