# "Mark as recurring" on a transaction: creates a manual recurring
# transaction from it, unless a series the user can see already covers it or
# another row holds the identity the new one would take.
class RecurringTransaction::TransactionMarker
  # reason is :covered or :exists.
  Blocker = Data.define(:reason, :recurring_transaction)

  attr_reader :transaction, :user

  def initialize(transaction, user:)
    @transaction = transaction
    @user = user
  end

  def blocker
    if (series = covering_series)
      Blocker.new(reason: :covered, recurring_transaction: series)
    elsif (series = RecurringTransaction.identity_taken_by(transaction))
      Blocker.new(reason: :exists, recurring_transaction: series)
    end
  end

  # Returns [created_series, nil] or [nil, blocker]. The check and the create
  # hold the entry lock the Allocator and the add-bill form take, so neither
  # can slip in between them. Raises ActiveRecord::RecordInvalid, and
  # ActiveRecord::RecordNotUnique when a concurrent request created the same
  # pattern first.
  def mark!
    created = found = nil

    Entry.transaction do
      RecurringTransaction::Allocator.lock_entry!(transaction.entry)
      found = blocker
      created = RecurringTransaction.create_from_transaction(transaction) unless found
    end

    [ created, found ]
  end

  private
    def covering_series
      transaction.entry.account.family.recurring_transactions.accessible_by(user).covering(transaction.entry)
    end
end
