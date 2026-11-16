# frozen_string_literal: true

# Resolves suspected duplicates the way the web does: merge or dismiss the
# suggested match (TransactionsController#merge_duplicate / #dismiss_duplicate),
# or pick the posted transaction a pending one became
# (PendingDuplicateMergesController#new / #create).
class Api::V1::TransactionDuplicatesController < Api::V1::BaseController
  include Api::V1::TransactionLookup

  CANDIDATES_PER_PAGE = 10
  MERGE_ERRORS = [
    ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed,
    ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout
  ].freeze

  before_action :ensure_read_scope, only: :pending_merge_candidates
  before_action :ensure_write_scope, except: :pending_merge_candidates
  before_action :set_transaction
  before_action -> { ensure_account_permission(:write) }, only: %i[merge_duplicate dismiss_duplicate]
  before_action -> { ensure_account_permission(:annotate) }, only: :pending_merge
  before_action :ensure_pending, only: %i[pending_merge_candidates pending_merge]

  # POST /api/v1/transactions/:id/merge_duplicate
  def merge_duplicate
    return render_error("not_pending", I18n.t("pending_duplicate_merges.set_transaction.pending_only")) unless @transaction.pending?
    return render_error("no_duplicate", "This transaction has no suggested duplicate") unless @transaction.has_potential_duplicate?

    posted_entry = @transaction.potential_duplicate_entry
    merge_into(posted_entry)
  end

  # POST /api/v1/transactions/:id/dismiss_duplicate
  def dismiss_duplicate
    return render_error("no_duplicate", "This transaction has no suggested duplicate") unless @transaction.dismiss_duplicate_suggestion!

    render_transaction(@transaction.reload)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("Failed to dismiss duplicate suggestion for transaction #{@transaction.id}: #{e.message}")
    render_error("dismiss_failed", I18n.t("transactions.dismiss_duplicate.failure"))
  end

  # GET /api/v1/transactions/:id/pending_merge_candidates
  def pending_merge_candidates
    offset = [ params[:offset].to_i, 0 ].max
    entries = @transaction.pending_duplicate_candidates(limit: CANDIDATES_PER_PAGE + 1, offset: offset).to_a
    has_more = entries.size > CANDIDATES_PER_PAGE
    entries = entries.first(CANDIDATES_PER_PAGE)

    transactions_by_id = Transaction
      .where(id: entries.map(&:entryable_id))
      .includes(
        { entry: :account }, :category, :merchant, :tags,
        transfer_as_outflow: { inflow_transaction: { entry: :account } },
        transfer_as_inflow: { outflow_transaction: { entry: :account } }
      )
      .index_by(&:id)
    @candidates = entries.filter_map { |entry| transactions_by_id[entry.entryable_id] }
    @split_parent_entry_ids = split_parent_entry_ids_for(@candidates)
    @offset = offset
    @limit = CANDIDATES_PER_PAGE
    @has_more = has_more

    render :pending_merge_candidates
  end

  # POST /api/v1/transactions/:id/pending_merge
  def pending_merge
    posted_entry_id = params.dig(:pending_merge, :posted_entry_id).presence
    return render_error("validation_failed", I18n.t("pending_duplicate_merges.create.no_posted_selected")) unless posted_entry_id.is_a?(String)

    posted_entry = @transaction.eligible_posted_entry_for_merge(posted_entry_id) if valid_uuid?(posted_entry_id)
    return render_error("invalid_posted_entry", I18n.t("pending_duplicate_merges.create.invalid_transaction")) unless posted_entry

    merge_into(posted_entry, record_match: true)
  end

  private

    def set_transaction
      load_accessible_transaction(params[:id])
    end

    def ensure_read_scope
      authorize_scope!(:read)
    end

    def ensure_write_scope
      authorize_scope!(:write)
    end

    # Same rule as AccountAuthorizable#require_account_permission!: :write is
    # owner or full_control, :annotate also admits a read_write share.
    def ensure_account_permission(level)
      return if performed?

      permission = @entry.account.permission_for(current_resource_owner)
      allowed = case level
      when :write then permission.in?([ :owner, :full_control ])
      when :annotate then permission == :owner || permission.to_s.in?(AccountShare::ANNOTATE_PERMISSIONS)
      end
      return if allowed

      render json: {
        error: "forbidden",
        message: "You do not have permission to modify this account"
      }, status: :forbidden
    end

    def ensure_pending
      return if performed?
      return if @transaction.pending?

      render_error("not_pending", I18n.t("pending_duplicate_merges.set_transaction.pending_only"))
    end

    def merge_into(posted_entry, record_match: false)
      merged = if record_match
        @transaction.merge_with_posted_entry!(posted_entry)
      else
        posted_entry.present? && @transaction.merge_with_duplicate!
      end
      return render_error("merge_failed", I18n.t("transactions.merge_duplicate.failure")) unless merged

      render_transaction(posted_entry.reload.entryable)
    rescue *MERGE_ERRORS => e
      Rails.logger.error("Failed to merge duplicate transaction #{@transaction.id}: #{e.message}")
      render_error("merge_failed", I18n.t("transactions.merge_duplicate.failure"))
    end

    def render_transaction(transaction)
      @transaction = transaction
      render "api/v1/transactions/show"
    end

    def render_error(error, message)
      render json: { error: error, message: message }, status: :unprocessable_entity
    end
end
