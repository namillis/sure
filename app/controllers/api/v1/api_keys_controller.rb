# frozen_string_literal: true

# The signed-in user's own API keys, as Settings::ApiKeysController manages them.
# Unlike the web's key page, the full key is only ever returned by #create.
class Api::V1::ApiKeysController < Api::V1::BaseController
  CREATE_LIMIT = 10
  CREATE_WINDOW = 1.hour

  before_action -> { authorize_scope!(:read) }, only: :index
  before_action -> { authorize_scope!(:read_write) }, only: %i[create destroy]
  rate_limit to: CREATE_LIMIT, within: CREATE_WINDOW, by: -> { current_resource_owner.id }, only: :create,
    name: "api-key-create", with: -> { render_create_rate_limited }
  before_action :set_managed_api_key, only: :destroy

  def index
    @api_keys = current_resource_owner.api_keys.active.visible.order(created_at: :desc)
    render :index
  end

  def create
    plain_key = ApiKey.generate_secure_key
    @managed_api_key = current_resource_owner.api_keys.build(api_key_params.merge(source: "web"))
    @managed_api_key.key = plain_key
    audit_log_failed = false

    ActiveRecord::Base.transaction do
      @managed_api_key.save!

      begin
        SecurityAuditLog.log_api_key_created!(user: current_resource_owner, api_key: @managed_api_key, request: request)
      rescue ActiveRecord::ActiveRecordError => e
        Rails.logger.error("[Api::V1::ApiKeys] Failed to write audit log for created key: #{e.message}")
        audit_log_failed = true
        raise ActiveRecord::Rollback
      end
    end

    if audit_log_failed
      message = "The API key could not be created"
      return render_json({ error: "creation_failed", message: message, errors: [ message ] }, status: :unprocessable_entity)
    end

    @plain_key = plain_key
    render :create, status: :created
  rescue ActiveRecord::RecordInvalid
    messages = @managed_api_key.errors.full_messages
    render_json({ error: "validation_failed", message: messages.to_sentence, errors: messages }, status: :unprocessable_entity)
  end

  def destroy
    if @managed_api_key.id == @api_key&.id
      message = "This key is authenticating the current request; revoke it with another key or on the web"
      return render_json({ error: "cannot_revoke_current_key", message: message, errors: [ message ] },
        status: :unprocessable_entity)
    end

    @managed_api_key.revoke!

    begin
      SecurityAuditLog.log_api_key_revoked!(user: current_resource_owner, api_key: @managed_api_key, request: request)
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.error("[Api::V1::ApiKeys] Failed to write audit log for revoked key #{@managed_api_key.id}: #{e.message}")
    end

    head :no_content
  end

  private

    # `.visible` keeps the demo monitoring key out of reach, as on the web.
    def set_managed_api_key
      raise ActiveRecord::RecordNotFound unless valid_uuid?(params[:id])

      @managed_api_key = current_resource_owner.api_keys.active.visible.find(params[:id])
    end

    def api_key_params
      permitted = params.require(:api_key).permit(:name, :scopes, scopes: [])
      permitted[:scopes] = Array(permitted[:scopes]) if permitted.key?(:scopes)
      permitted
    end

    def render_create_rate_limited
      message = "Too many API keys created. Try again later."
      render_json({ error: "rate_limit_exceeded", message: message, errors: [ message ] }, status: :too_many_requests)
    end
end
