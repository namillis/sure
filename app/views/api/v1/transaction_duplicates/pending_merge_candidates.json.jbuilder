# frozen_string_literal: true

json.candidates @candidates do |transaction|
  json.partial! "api/v1/transactions/transaction", transaction: transaction, split_parent_ids: @split_parent_entry_ids
end

json.pagination do
  json.offset @offset
  json.limit @limit
  json.has_more @has_more
end
