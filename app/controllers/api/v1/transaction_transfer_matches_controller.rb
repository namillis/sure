# frozen_string_literal: true

# Marking a transaction as one side of a transfer, and undoing it: the web's
# "match as transfer" dialog (TransferMatchesController), its "Reject match"
# button on a matched row (TransfersController#update with status rejected)
# and its "Not a transfer" button on a transfer hint
# (TransferMatchesController#destroy).
class Api::V1::TransactionTransferMatchesController < Api::V1::BaseController
  include Api::V1::TransactionLookup

  MATCH_METHODS = %w[existing new].freeze

  TRANSACTION_PRELOADS = [
    { entry: :account },
    :category, :merchant, :tags,
    { transfer_as_outflow: { inflow_transaction: { entry: :account } } },
    { transfer_as_inflow: { outflow_transaction: { entry: :account } } }
  ].freeze

  before_action :ensure_read_scope, only: :candidates
  before_action :ensure_write_scope, only: %i[create destroy]
  before_action :set_transaction

  # GET /api/v1/transactions/:id/transfer_candidates
  def candidates
    match_options = Transfer::MatchOptions.new(@entry, user: current_resource_owner)

    # The dialog lists split children too, but Transfer::Matcher (which create
    # uses) refuses them, so only offer pairs create accepts.
    matcher = Transfer::Matcher.new(@transaction)
    matchable_ids = matcher.candidates.map { |row| matcher.counterpart_id(row) }.to_set
    candidate_entries = match_options.candidate_entries.select { |entry| matchable_ids.include?(entry.entryable_id) }

    transactions_by_id = Transaction.where(id: candidate_entries.map(&:entryable_id)).preload(*TRANSACTION_PRELOADS).index_by(&:id)
    @candidate_transactions = candidate_entries.filter_map { |entry| transactions_by_id[entry.entryable_id] }
    @accounts = match_options.accounts
    @split_parent_entry_ids = Set.new

    render :candidates
  end

  # POST /api/v1/transactions/:id/transfer_match
  def create
    return unless ensure_account_write_permission(@entry.account)

    match_method = transfer_match_params[:method].to_s
    unless MATCH_METHODS.include?(match_method)
      return render_validation_error("method must be one of: #{MATCH_METHODS.join(', ')}")
    end

    matcher = Transfer::Matcher.new(@transaction)

    @transfer = if match_method == "new"
      target_account = find_target_account
      return unless target_account
      return unless ensure_account_write_permission(target_account)

      matcher.match_to_account!(target_account)
    else
      counterpart = find_matched_transaction
      return unless counterpart
      return unless ensure_account_write_permission(counterpart.entry.account)

      matcher.match_with!(counterpart)
    end

    render_transfer(status: :created)
  rescue Transfer::Matcher::Error => e
    render_json({ error: "validation_failed", message: e.message, errors: [ e.message ], reason: e.code.to_s }, status: :unprocessable_entity)
  end

  # DELETE /api/v1/transactions/:id/transfer_match
  #
  # A matched transaction is unmatched as the web's "Reject match" does: the
  # transfer is removed and the pair recorded as a RejectedTransfer, so
  # auto-matching does not pair them again. An unmatched transaction gets the
  # web's "Not a transfer" on its hint: every pair the hint offered is recorded
  # as rejected.
  def destroy
    transfer = @transaction.transfer

    if transfer
      return unless ensure_account_write_permission(transfer.unlink_permission_account_for(current_resource_owner))

      transfer.with_lock { transfer.reject! }
    else
      return unless ensure_account_write_permission(@entry.account)

      current_resource_owner.family.dismiss_transfer_hint!(@transaction, user: current_resource_owner)
    end

    @transaction = Transaction.preload(*TRANSACTION_PRELOADS).find(@transaction.id)
    render "api/v1/transactions/show"
  end

  private

    def ensure_write_scope
      authorize_scope!(:write)
    end

    def set_transaction
      load_accessible_transaction(params[:id])
    end

    def transfer_match_params
      @transfer_match_params ||= begin
        raw = params[:transfer_match]
        raw.respond_to?(:permit) ? raw.permit(:method, :matched_entry_id, :target_account_id) : ActionController::Parameters.new.permit
      end
    end

    # Owner or full_control, the web's require_account_permission!(account).
    def ensure_account_write_permission(account)
      return true if account.permission_for(current_resource_owner).in?([ :owner, :full_control ])

      render_json({ error: "forbidden", message: "You do not have write access to this account" }, status: :forbidden)
      false
    end

    def find_target_account
      account_id = transfer_match_params[:target_account_id]
      account = current_resource_owner.family.accounts.accessible_by(current_resource_owner).find_by(id: account_id) if valid_uuid?(account_id)
      return account if account

      render_json({ error: "not_found", message: "Target account not found" }, status: :not_found)
      nil
    end

    def find_matched_transaction
      entry_id = transfer_match_params[:matched_entry_id]
      entry = if valid_uuid?(entry_id)
        current_resource_owner.family.entries
          .joins(:account).merge(Account.accessible_by(current_resource_owner))
          .find_by(id: entry_id, entryable_type: "Transaction")
      end
      return entry.transaction if entry

      render_json({ error: "not_found", message: "Matched transaction not found" }, status: :not_found)
      nil
    end

    def render_transfer(status:)
      @transfer = Transfer.preload(
        inflow_transaction: TRANSACTION_PRELOADS,
        outflow_transaction: TRANSACTION_PRELOADS
      ).find(@transfer.id)

      render :create, status: status
    end
end
