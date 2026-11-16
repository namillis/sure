# frozen_string_literal: true

# Which routes a web handoff may start on, and which a handoff session may reach afterwards. Both
# are decided on the recognized controller#action and params, never on a prefix of the path.
class WebHandoff::RoutePolicy
  MAX_PATH_BYTES = 2048
  # One leading slash, no "//host", no backslashes and no control characters.
  SAFE_RELATIVE_PATH = %r{\A/(?![/\\])[^[:cntrl:]\\]*\z}
  PROVIDER_CONTROLLER = %r{\A[a-z0-9]+(?:_[a-z0-9]+)*_items(?:/[a-z0-9_]+)?\z}
  PROVIDER_KEY = /\A[a-z0-9_]+\z/

  # Pages a connect or reconnect flow starts on, or continues to.
  PROVIDER_ENTRY_ACTIONS = %w[
    connect edit new new_wallet select_accounts select_bank select_existing_account select_profiles
    setup_accounts
  ].freeze
  SETTINGS_ENTRY_ACTIONS = %w[show connect_form].freeze
  CANCELLABLE_ACTIONS = %w[select_accounts select_bank select_existing_account select_profiles setup_accounts].freeze

  # The providers page minus #update, which edits instance-wide provider credentials.
  SETTINGS_SESSION_ACTIONS = %w[show connect_form sync sync_all].freeze

  # Pages a completed or abandoned flow lands on.
  FINISH_ROUTES = {
    "settings/providers" => %w[show],
    "accounts" => %w[index show],
    "pages" => %w[dashboard]
  }.freeze

  class << self
    def entry_path_allowed?(path)
      recognized = recognize_entry_path(path)
      return false unless recognized

      controller = recognized[:controller]
      action = recognized[:action]

      if controller == "settings/providers"
        SETTINGS_ENTRY_ACTIONS.include?(action) && valid_provider_key?(recognized)
      else
        provider_controller?(controller) && PROVIDER_ENTRY_ACTIONS.include?(action) && valid_member_id?(recognized)
      end
    end

    # Every action of a provider *_items controller (callbacks, setup, select, link, complete,
    # sync) plus the providers page.
    def session_request_allowed?(controller_path, action_name)
      return SETTINGS_SESSION_ACTIONS.include?(action_name) if controller_path == "settings/providers"

      provider_controller?(controller_path)
    end

    def provider_controller?(controller_path)
      controller_path.is_a?(String) && controller_path.match?(PROVIDER_CONTROLLER)
    end

    # Pages whose Cancel link leaves the flow. New and edit pages are left out: Plaid's update
    # mode also navigates away from its edit page when it succeeds.
    def cancellable_flow_page?(recognized)
      recognized.present? && provider_controller?(recognized[:controller]) &&
        CANCELLABLE_ACTIONS.include?(recognized[:action])
    end

    # The recognized route of a same-host location, or nil.
    def recognize_location(location, host:)
      uri = URI.parse(location.to_s)
      return if uri.host.present? && uri.host != host
      return if uri.scheme.present? && !%w[http https].include?(uri.scheme)
      return if uri.path.blank?

      Rails.application.routes.recognize_path(uri.path, method: :get)
    rescue URI::InvalidURIError, ActionController::RoutingError
      nil
    end

    def finish_route?(recognized)
      return false unless recognized

      FINISH_ROUTES.fetch(recognized[:controller], []).include?(recognized[:action])
    end

    private
      def recognize_entry_path(path)
        return unless path.is_a?(String) && path.bytesize <= MAX_PATH_BYTES
        return unless path.match?(SAFE_RELATIVE_PATH)

        uri = URI.parse(path)
        return if uri.scheme || uri.host || uri.userinfo || uri.fragment

        recognized = Rails.application.routes.recognize_path(uri.path, method: :get)
        return unless recognized[:controller].present? && recognized[:action].present?
        return unless recognized[:format].nil? || recognized[:format] == "html"

        recognized
      rescue URI::InvalidURIError, ActionController::RoutingError
        nil
      end

      def valid_provider_key?(recognized)
        recognized[:provider_key].nil? || recognized[:provider_key].match?(PROVIDER_KEY)
      end

      def valid_member_id?(recognized)
        recognized[:id].nil? || UuidFormat.valid?(recognized[:id])
      end
  end
end
