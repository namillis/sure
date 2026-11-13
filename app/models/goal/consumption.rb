# Records a spend against a goal on behalf of one viewer. Shared by the web
# dialog and the API so both resolve the account and the outflow the same way.
#
# Every lookup is narrowed to the goal's links the viewer may see. A goal can
# be backed by a private account, and every half of that leak matters: the
# dialog would name an account the reader is not allowed to know exists, the
# outflow panel would list its transactions, and a write would reduce its
# earmark, the figures moving afterwards saying how much was in it.
class Goal::Consumption
  attr_reader :goal

  def initialize(goal, user:)
    @goal = goal
    @user = user
  end

  def eligible_accounts
    @eligible_accounts ||= begin
      linked = goal.linked_accounts
      visible_ids = @user.accessible_accounts.where(id: linked.map(&:id)).pluck(:id).to_set
      linked.select { |account| visible_ids.include?(account.id) }
    end
  end

  def withdrawal_detector
    Goal::WithdrawalDetector.new(goal, accounts: eligible_accounts)
  end

  # Returns the amount recorded, in goal currency. Raises
  # Goal::ConsumptionRefused with the rule that refused.
  def record!(amount: nil, account_id: nil, transaction_id: nil)
    txn = consumption_transaction(transaction_id)
    amount = txn ? goal.convert_money!(txn.entry.amount_money, date: txn.entry.date).amount : amount.to_d

    goal.consume!(amount, account: consumption_account(account_id, txn), transaction: txn)
    amount
  rescue Money::ConversionError
    raise Goal::ConsumptionRefused.new(:missing_exchange_rate)
  end

  private
    # Attributing a detected outflow: the transaction says both how much and
    # from where, so neither is taken from the caller.
    def consumption_transaction(transaction_id)
      return nil if transaction_id.blank?

      withdrawal_detector.unattributed_outflows(limit: 50)
                         .find_by(entryable_id: transaction_id)
                         &.entryable ||
        raise(Goal::ConsumptionRefused.new(:transaction_not_found))
    end

    # A blank id means "the goal has one link, use it" and the model decides
    # whether that is true. An id that resolves to nothing is refused here
    # rather than falling back to nil: on a single-link goal, nil would consume
    # from that link and the user would see a spend recorded against an account
    # they did not name.
    def consumption_account(account_id, txn)
      eligible = eligible_accounts
      raise Goal::ConsumptionRefused.new(:account_not_linked) if eligible.empty?

      # An attributed outflow names its own account; a typed spend names one
      # only when the goal has a choice to offer.
      account_id = txn.entry.account_id if txn

      if account_id.present?
        return eligible.find { |account| account.id.to_s == account_id.to_s } ||
          raise(Goal::ConsumptionRefused.new(:account_not_linked))
      end

      # Named explicitly even when the goal has several links, because the one
      # the viewer can reach is not necessarily the one the model would pick on
      # its own. With more than one eligible link it stays nil, and the model
      # refuses rather than guessing.
      eligible.size == 1 ? eligible.first : nil
    end
end
