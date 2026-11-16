# frozen_string_literal: true

# Creates token-based provider connections and finishes their account setup,
# as the providers' web create and setup_accounts / complete_account_setup do.
# Every one of those web actions is admin-only (require_admin!).
class Api::V1::ProviderConnectionSetupsController < Api::V1::BaseController
  before_action -> { authorize_scope!(:read) }, only: :pending_accounts
  before_action -> { authorize_scope!(:read_write) }, only: %i[create complete_setup]
  before_action :require_admin
  before_action :set_setup, only: %i[pending_accounts complete_setup]

  rescue_from ProviderConnectionManager::Unprocessable do |error|
    render_json({ error: error.code, message: error.message, errors: [ error.message ] }, status: :unprocessable_entity)
  end

  def create
    provider_key = params[:provider].to_s
    return render_validation_error("provider is required") if provider_key.blank?

    setup_class = ProviderConnectionSetup.setup_class_for(provider_key)
    return render_validation_error("connection must be an object") unless params[:connection].is_a?(ActionController::Parameters)

    attributes = params[:connection].permit(*setup_class.permitted_attributes)
    item = ProviderConnectionSetup.create(current_resource_owner.family, provider_key, attributes)

    unless item.persisted?
      messages = item.errors.full_messages
      return render_json({ error: "validation_failed", message: messages.to_sentence, errors: messages },
        status: :unprocessable_entity)
    end

    @setup = ProviderConnectionSetup.new(ProviderConnectionManager.find(current_resource_owner.family, item.id, provider_key: provider_key))
    render_setup(status: :created)
  end

  def pending_accounts
    @setup.import_accounts!

    render_json({
      data: @setup.pending_accounts,
      awaiting_accounts: @setup.awaiting_accounts?
    })
  end

  def complete_setup
    setup_params = params.permit(:sync_start_date, accounts: %i[id import accountable_type subtype link_to_account_id])
    @created_accounts = @setup.complete!(setup_params[:accounts], sync_start_date: setup_params[:sync_start_date])
    render_setup(status: :ok)
  end

  private

    def require_admin
      return if current_resource_owner&.admin?

      render_json({ error: "forbidden", message: "Only a family admin can connect providers" }, status: :forbidden)
    end

    def set_setup
      raise ActiveRecord::RecordNotFound unless valid_uuid?(params[:id])

      connection = ProviderConnectionManager.find(current_resource_owner.family, params[:id], provider_key: params[:provider])
      raise ActiveRecord::RecordNotFound if connection.item.try(:scheduled_for_deletion?)

      @setup = ProviderConnectionSetup.new(connection)
    end

    def render_setup(status:)
      item = @setup.item
      @provider_connection = ProviderConnectionStatus.for_family(current_resource_owner.family).find do |row|
        row[:id] == item.id && row[:provider] == @setup.connection.key
      end
      render :show, status: status
    end
end
