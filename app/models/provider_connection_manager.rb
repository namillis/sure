# frozen_string_literal: true

# Sync and disconnect for one provider connection, as the API exposes them.
# Each provider's steps mirror its web controller's #sync and #destroy
# (app/controllers/<provider>_items_controller.rb); keep them in step when those change.
class ProviderConnectionManager
  class Error < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  class Forbidden < Error; end
  class Unprocessable < Error; end

  # unlink: how the web's #destroy detaches accounts before destroy_later.
  #   :none        -- destroy_later only
  #   :raise       -- unlink_all!, an exception propagates
  #   :best_effort -- unlink_all!, an exception is logged and ignored
  #   :abort_on_raise -- an exception aborts the disconnect
  #   :strict      -- any per-account unlink error, or an exception, aborts the disconnect
  UNLINK_MODES = {
    "akahu" => :abort_on_raise,
    "brex" => :raise,
    "coinspot" => :strict,
    "enable_banking" => :best_effort,
    "fio" => :strict,
    "ibkr" => :best_effort,
    "kraken" => :raise,
    "lunchflow" => :best_effort,
    "mercury" => :best_effort,
    "monobank" => :strict,
    "redbark" => :strict,
    "sharesight" => :raise,
    "simplefin" => :best_effort,
    "sophtron" => :best_effort,
    "trade_republic" => :strict,
    "trading212" => :raise,
    "truelayer" => :raise,
    "up" => :strict,
    "wise" => :raise
  }.freeze

  # Item ids are UUIDs in separate tables, so `provider_key` (the "provider" field the
  # list returns) is only needed to tell apart two connections that share an id.
  def self.find(family, id, provider_key: nil)
    providers = ProviderConnectionStatus::PROVIDERS
    providers = providers.select { |provider| provider[:key] == provider_key } if provider_key.present?

    matches = providers.filter_map do |provider|
      item = family.public_send(provider[:association]).find_by(id: id)
      new(provider, item) if item
    end

    raise ActiveRecord::RecordNotFound if matches.empty?
    raise Unprocessable.new("ambiguous_connection", "More than one connection has this id; pass the provider parameter") if matches.size > 1

    matches.first
  end

  attr_reader :provider, :item

  def initialize(provider, item)
    @provider = provider
    @item = item
  end

  def key
    provider[:key]
  end

  def sync!(user)
    authorize!(user)

    case key
    when "financekit"
      raise Unprocessable.new("sync_not_supported", "FinanceKit connections are updated by the Wallet publisher on the device, not by a server sync")
    when "plaid"
      item.sync_later_with_provider_refresh
    when "fio"
      item.update!(history_unlock_required_at: nil) if item.history_unlock_required_at.present?
      item.sync_later unless item.syncing?
    when "sophtron"
      raise Unprocessable.new("manual_sync_required", "This Sophtron connection needs an interactive sync with a security code. Sync it on the web") if item.manual_sync_required?

      item.sync_later unless item.syncing?
    when "truelayer"
      raise Unprocessable.new("not_connected", "This TrueLayer connection is not authorized. Reconnect it on the web") unless item.connected?

      item.sync_later unless item.syncing?
    when "trade_republic"
      raise Unprocessable.new("reconnect_required", "This Trade Republic connection needs a new login. Log in again on the web") unless item.syncing? || item.ready_for_sync?

      item.sync_later unless item.syncing?
    else
      item.sync_later unless item.syncing?
    end
  end

  def disconnect!(user)
    authorize!(user)

    if key == "financekit"
      raise Unprocessable.new("disconnect_not_supported", "Disconnect FinanceKit connections with DELETE /api/v1/financekit/connections/:id")
    end

    unlink!
    item.revoke_session if key == "enable_banking"
    item.destroy_later
  end

  private

    # PlaidItemsController gates sync/destroy on ownership (ConnectorAuthorizable);
    # every other provider controller uses require_admin!.
    def authorize!(user)
      allowed = key == "plaid" ? item.manageable_by?(user) : user&.admin?
      raise Forbidden.new("forbidden", "Only a family admin can manage this connection") unless allowed
    end

    def unlink!
      case UNLINK_MODES.fetch(key, :none)
      when :raise
        item.unlink_all!(dry_run: false)
      when :best_effort
        begin
          item.unlink_all!(dry_run: false)
        rescue => e
          Rails.logger.warn("#{provider[:type]} unlink during destroy failed: #{e.class} - #{e.message}")
        end
      when :abort_on_raise
        begin
          item.unlink_all!(dry_run: false)
        rescue => e
          unlink_failed!(e)
        end
      when :strict
        begin
          results = item.unlink_all!(dry_run: false)
        rescue => e
          unlink_failed!(e)
        end
        unlink_failed! if results.any? { |result| result[:error].present? }
      end
    end

    def unlink_failed!(error = nil)
      Rails.logger.warn("#{provider[:type]} unlink during destroy failed: #{error.class} - #{error.message}") if error
      raise Unprocessable.new("unlink_failed", "Some accounts could not be unlinked from this connection, so it was not disconnected")
    end
end
