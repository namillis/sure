# What the "match as transfer" dialog offers a user for one entry: the
# accounts a new counterpart can be created in, and the existing counterpart
# entries (Transaction#transfer_match_candidates) on accounts the user can
# write to, in candidate order.
class Transfer::MatchOptions
  attr_reader :entry, :user

  def initialize(entry, user:)
    @entry = entry
    @user = user
  end

  # Preloaded for the logo selects, which call Account#logo_url per option.
  def accounts
    @accounts ||= entry.account.family.accounts.writable_by(user).visible.alphabetically.where.not(id: entry.account_id)
      .includes(:account_providers, logo_attachment: :blob)
  end

  def candidate_entries
    @candidate_entries ||= begin
      counterpart_ids = entry.transaction.transfer_match_candidates.map do |candidate|
        entry.amount.negative? ? candidate.outflow_transaction_id : candidate.inflow_transaction_id
      end

      entries_by_transaction_id = Entry
        .where(entryable_type: "Transaction", entryable_id: counterpart_ids, account_id: accounts.map(&:id))
        .includes(account: [ :account_providers, { logo_attachment: :blob } ])
        .index_by(&:entryable_id)

      counterpart_ids.filter_map { |id| entries_by_transaction_id[id] }
    end
  end
end
