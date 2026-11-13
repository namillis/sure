# frozen_string_literal: true

amount_money = pledge.amount_money

json.id pledge.id
json.account_id pledge.account_id
json.account_name(accessible_account_ids.include?(pledge.account_id) ? pledge.account&.name : nil)
json.kind pledge.kind
json.status pledge.status
json.amount amount_money.format
json.amount_cents (amount_money.amount * amount_money.currency.minor_unit_conversion).round(0).to_i
json.currency pledge.currency
json.days_left pledge.days_left
json.expires_at pledge.expires_at
json.created_at pledge.created_at
