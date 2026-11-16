# frozen_string_literal: true

json.transfer do
  json.partial! "api/v1/transfers/transfer", transfer: @transfer
end

json.inflow do
  json.partial! "api/v1/transactions/transaction", transaction: @transfer.inflow_transaction
end

json.outflow do
  json.partial! "api/v1/transactions/transaction", transaction: @transfer.outflow_transaction
end
