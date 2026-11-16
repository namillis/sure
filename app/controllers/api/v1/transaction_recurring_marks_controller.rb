# frozen_string_literal: true

# "Mark as recurring" on a transaction (TransactionsController#mark_as_recurring).
class Api::V1::TransactionRecurringMarksController < Api::V1::BaseController
  include Api::V1::TransactionLookup

  before_action :ensure_write_scope
  before_action :set_transaction
  before_action :ensure_account_write_permission

  # POST /api/v1/transactions/:id/mark_as_recurring
  def create
    created, blocker = RecurringTransaction::TransactionMarker.new(@transaction, user: current_resource_owner).mark!
    return render_conflict(blocker) if blocker

    @recurring_transaction = created
    render :create, status: :created
  rescue ActiveRecord::RecordNotUnique
    # A concurrent request created the same pattern after the check.
    render_conflict(RecurringTransaction::TransactionMarker.new(@transaction, user: current_resource_owner).blocker)
  rescue ActiveRecord::RecordInvalid => e
    render_json({
      error: "validation_failed",
      message: "Failed to create recurring transaction",
      errors: e.record.errors.full_messages
    }, status: :unprocessable_entity)
  end

  private

    def ensure_write_scope
      authorize_scope!(:write)
    end

    def set_transaction
      load_accessible_transaction(params[:id])
    end

    def ensure_account_write_permission
      return if performed?
      return if @entry.account.permission_for(current_resource_owner).in?([ :owner, :full_control ])

      render_json({ error: "forbidden", message: "You do not have write access to this account" }, status: :forbidden)
    end

    def render_conflict(blocker)
      @message = blocker&.reason == :covered ? t("recurring_transactions.already_covered") : t("recurring_transactions.already_exists")
      series = blocker&.recurring_transaction
      series = nil if series && !current_resource_owner.family.recurring_transactions.accessible_by(current_resource_owner).exists?(series.id)

      @recurring_transaction = series
      render :conflict, status: :conflict
    end
end
