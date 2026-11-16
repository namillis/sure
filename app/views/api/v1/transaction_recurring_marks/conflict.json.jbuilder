# frozen_string_literal: true

json.error "conflict"
json.message @message
json.errors [ @message ]

if @recurring_transaction
  json.recurring_transaction do
    json.partial! "api/v1/recurring_transactions/recurring_transaction", recurring_transaction: @recurring_transaction
  end
else
  json.recurring_transaction nil
end
