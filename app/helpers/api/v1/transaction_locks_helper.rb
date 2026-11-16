# frozen_string_literal: true

module Api::V1::TransactionLocksHelper
  # Accounts whose transactions show the web's reconcile badge for this user:
  # the family turned manual reconciliation on, the account has no bank sync,
  # and the user may write to it. One query per request, like
  # TransactionsHelper#can_reconcile_account?.
  def api_reconcilable_account_ids
    @api_reconcilable_account_ids ||= if Current.user&.family&.manual_reconciliation?
      Account.writable_by(Current.user).manual.where(family_id: Current.user.family_id).pluck(:id).to_set
    else
      Set.new
    end
  end
end
