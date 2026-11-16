# frozen_string_literal: true

json.candidates @candidate_transactions do |transaction|
  json.transaction do
    json.partial! "api/v1/transactions/transaction", transaction: transaction, split_parent_ids: @split_parent_entry_ids
  end
  json.account do
    json.id transaction.entry.account.id
    json.name transaction.entry.account.name
  end
end

json.accounts @accounts do |account|
  json.id account.id
  json.name account.name
  json.account_type account.accountable_type.underscore
  json.currency account.currency
end
