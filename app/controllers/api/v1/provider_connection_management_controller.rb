# frozen_string_literal: true

class Api::V1::ProviderConnectionManagementController < Api::V1::BaseController
  before_action -> { authorize_scope!(:read_write) }
  before_action :reject_guest_writes!
  before_action :set_connection

  rescue_from ProviderConnectionManager::Forbidden do |error|
    render_json({ error: error.code, message: error.message }, status: :forbidden)
  end

  rescue_from ProviderConnectionManager::Unprocessable do |error|
    render_json({ error: error.code, message: error.message, errors: [ error.message ] }, status: :unprocessable_entity)
  end

  def sync
    @connection.sync!(current_resource_owner)
    render_connection
  end

  def destroy
    @connection.disconnect!(current_resource_owner)
    render_connection
  end

  private

    def set_connection
      raise ActiveRecord::RecordNotFound unless valid_uuid?(params[:id])

      @connection = ProviderConnectionManager.find(current_resource_owner.family, params[:id], provider_key: params[:provider])
    end

    def render_connection
      family = current_resource_owner.family
      @provider_connection = ProviderConnectionStatus.for_family(family).find do |status|
        status[:id] == @connection.item.id && status[:provider] == @connection.key
      end
      render :show, status: :accepted
    end
end
