# frozen_string_literal: true

# TransactionsController#unlock and #reconcile for the API.
class Api::V1::TransactionLocksController < Api::V1::BaseController
  include Api::V1::TransactionLookup

  before_action :ensure_write_scope
  before_action :set_transaction
  before_action :ensure_account_write_permission

  # POST /api/v1/transactions/:id/unlock
  def unlock
    @entry.unlock_for_sync!

    render_transaction
  end

  # PATCH /api/v1/transactions/:id/reconcile
  def reconcile
    family = current_resource_owner.family
    return render_error("reconciliation_disabled", I18n.t("transactions.reconcile.unavailable")) unless family.manual_reconciliation?
    return render_error("not_manual_account", I18n.t("transactions.reconcile.not_manual_account")) unless @entry.account.manual?

    @entry.advance_reconciled_status!

    render_transaction
  rescue ActiveRecord::RecordInvalid => e
    DebugLogEntry.capture(
      category: "reconciliation",
      level: "error",
      message: "Failed to update reconciled_status for transaction #{@transaction.id}: #{e.message}",
      source: "Api::V1::TransactionLocksController#reconcile",
      family: family,
      user: current_resource_owner,
      account: @entry.account,
      metadata: {
        transaction_id: @transaction.id,
        entry_id: @entry.id,
        error_class: e.class.name,
        error_message: e.message
      }
    )
    render_error("reconcile_failed", I18n.t("transactions.reconcile.failure"))
  end

  private

    def set_transaction
      load_accessible_transaction(params[:id])
    end

    def ensure_write_scope
      authorize_scope!(:write)
    end

    # The web requires owner or full_control (require_account_permission!'s :write) for both actions.
    def ensure_account_write_permission
      return if performed?
      return if @entry.account.permission_for(current_resource_owner).in?([ :owner, :full_control ])

      render json: {
        error: "forbidden",
        message: "You do not have permission to modify this account"
      }, status: :forbidden
    end

    def render_transaction
      @transaction.reload
      render "api/v1/transactions/show"
    end

    def render_error(error, message)
      render json: { error: error, message: message }, status: :unprocessable_entity
    end
end
