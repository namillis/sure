# frozen_string_literal: true

# Converts a transaction into a trade, as the web "Convert to trade" modal
# does (TransactionsController#convert_to_trade / #create_trade_from_transaction).
# Both go through Transaction::TradeConversion.
class Api::V1::TransactionTradeConversionsController < Api::V1::BaseController
  include Api::V1::TransactionLookup

  before_action :ensure_read_scope, only: :show
  before_action :ensure_write_scope, only: :create
  before_action :set_transaction
  before_action :ensure_account_write_permission

  # GET /api/v1/transactions/:id/convert_to_trade
  def show
    @conversion = Transaction::TradeConversion.new(@transaction)
    @conversion.ensure_convertible!
    @security_options = @conversion.held_securities
    @prices_by_security_id = Security::Price
      .where(security_id: @security_options.map(&:id), date: Date.current)
      .index_by(&:security_id)

    render :show
  rescue Transaction::TradeConversion::Error => e
    render_conversion_error(e)
  end

  # POST /api/v1/transactions/:id/convert_to_trade
  def create
    label = conversion_params[:investment_activity_label]
    if label.present? && !label.in?(Transaction::TradeConversion::ACTIVITY_LABELS)
      message = "investment_activity_label must be one of: #{Transaction::TradeConversion::ACTIVITY_LABELS.join(', ')}"
      return render json: { error: "validation_failed", message: message, errors: [ message ] },
        status: :unprocessable_entity
    end

    trade_entry = Transaction::TradeConversion.new(@transaction, conversion_params).convert!
    trade_entry.sync_account_later

    @trade = trade_entry.trade
    render :create, status: :created
  rescue Transaction::TradeConversion::Error => e
    render_conversion_error(e)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
    render json: {
      error: "validation_failed",
      message: I18n.t("transactions.convert_to_trade.errors.conversion_failed", error: e.message),
      errors: e.record&.errors&.full_messages.presence || [ e.message ]
    }, status: :unprocessable_entity
  end

  private

    def ensure_write_scope
      authorize_scope!(:write)
    end

    def set_transaction
      load_accessible_transaction(params[:id])
    end

    # The web requires write access to the account for both the form and the
    # submit (require_account_permission! defaults to :write).
    def ensure_account_write_permission
      return if performed?
      return if @entry.account.permission_for(current_resource_owner).in?([ :owner, :full_control ])

      render json: {
        error: "forbidden",
        message: "You do not have write access to this account"
      }, status: :forbidden
    end

    def conversion_params
      raw = params[:trade]
      return {} unless raw.respond_to?(:permit)

      raw.permit(
        :security_id, :ticker, :custom_ticker, :exchange_operating_mic,
        :qty, :price, :investment_activity_label, :trade_name
      ).to_h.except(:security_id).merge(security_id_param(raw))
    end

    # "__custom__" is a sentinel of the web form's select, not an id.
    def security_id_param(raw)
      value = raw[:security_id]
      value.present? && value != "__custom__" ? { security_id: value } : {}
    end

    def render_conversion_error(error)
      render json: {
        error: error.key.to_s,
        message: error.message,
        errors: [ error.message ]
      }, status: :unprocessable_entity
    end
end
