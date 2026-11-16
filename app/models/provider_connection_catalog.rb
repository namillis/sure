# frozen_string_literal: true

# The connections a user may add, and where to repair one that needs attention, as the web offers
# them: Plaid from its link page when the instance has Plaid credentials (members too, because a
# Plaid credential is scoped to one connection), and every family provider panel of
# /settings/providers for admins.
class ProviderConnectionCatalog
  class << self
    def available_for(user)
      return [] if user.nil? || user.guest?

      (plaid_entries(user) + panel_entries(user)).sort_by { |entry| entry[:name].downcase }
    end

    # Adds reconnect_path to ProviderConnectionStatus rows: the page the web sends the user to when
    # the connection needs updating, or nil when it doesn't or the user can't open that page.
    def with_reconnect_paths(rows, user:)
      plaid_ids = rows.select { |row| row[:provider] == "plaid" && needs_reconnect?(row) }.map { |row| row[:id] }
      plaid_items = plaid_ids.any? ? user.family.plaid_items.where(id: plaid_ids).index_by(&:id) : {}

      rows.map { |row| row.merge(reconnect_path: reconnect_path_for(row, user, plaid_items)) }
    end

    private
      def plaid_entries(user)
        Provider::PlaidAdapter.connection_configs(family: user.family).filter_map do |config|
          next unless user.admin? || (config[:member_connectable] && user.member?)

          entry(provider: "plaid", key: config[:key], name: config[:name], connect_path: config[:new_account_path].call(nil, nil))
        end
      end

      def panel_entries(user)
        return [] unless user.admin?

        Settings::ProvidersController::FAMILY_PANELS.filter_map do |panel|
          next unless can_connect?(user.family, panel[:key])

          entry(provider: panel[:key], key: panel[:key], name: panel[:title], connect_path: connect_form_path(panel[:key]))
        end
      end

      def entry(provider:, key:, name:, connect_path:)
        {
          provider: provider,
          key: key,
          name: name,
          connect_path: connect_path,
          kind: ProviderConnectionSetup::SETUP_CLASSES.key?(provider) ? "token" : "web"
        }
      end

      def can_connect?(family, provider_key)
        check = :"can_connect_#{provider_key}?"
        !family.respond_to?(check) || family.public_send(check)
      end

      def needs_reconnect?(row)
        row[:requires_update] == true || row[:status].to_s == "requires_update"
      end

      def reconnect_path_for(row, user, plaid_items)
        return unless needs_reconnect?(row)

        case row[:provider]
        when "plaid"
          item = plaid_items[row[:id]]
          url_helpers.edit_plaid_item_path(item) if item&.manageable_by?(user)
        when "simplefin"
          url_helpers.edit_simplefin_item_path(row[:id]) if user.admin?
        else
          connect_form_path(row[:provider]) if user.admin? && Settings::ProvidersController::FAMILY_PANELS_BY_KEY.key?(row[:provider])
        end
      end

      def connect_form_path(provider_key)
        url_helpers.connect_form_settings_providers_path(provider_key: provider_key)
      end

      def url_helpers
        Rails.application.routes.url_helpers
      end
  end
end
