# frozen_string_literal: true

# Loads the suggested duplicate of every row on a page in one query, for the
# duplicate_candidate field of the transaction partial.
module Api::V1::TransactionDuplicateCandidates
  extend ActiveSupport::Concern

  private

    def duplicate_candidate_entries_for(transactions)
      entry_ids = transactions.filter_map(&:potential_duplicate_entry_id)
      return {} if entry_ids.empty?

      account_ids = transactions.map { |transaction| transaction.entry.account_id }.uniq
      Entry.where(id: entry_ids, account_id: account_ids).index_by(&:id)
    end
end
