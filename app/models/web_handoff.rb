# frozen_string_literal: true

# One-time tokens that turn a Sure+ app API credential into a short-lived, restricted web session
# for a provider connect flow. Only a digest of the token is kept, in Rails.cache, so no table is
# needed; the token is single use and expires after TOKEN_TTL.
class WebHandoff
  TOKEN_TTL = 60.seconds
  TOKEN_BYTES = 32
  CACHE_PREFIX = "sure_plus:web_handoff:"
  CREDENTIAL_TYPES = %w[api_key oauth].freeze
  APP_CALLBACK_URL = "sureplus://connections/done"
  FINISH_STATUSES = %w[ok cancelled error].freeze
  APP_CALLBACK_URLS = FINISH_STATUSES.index_with { |status| "#{APP_CALLBACK_URL}?status=#{status}" }.freeze

  Grant = Data.define(:user_id, :path, :credential_type, :credential_id)

  class << self
    # Returns [token, expires_at]. The caller must have checked the path with RoutePolicy.
    def issue!(user:, path:, credential_type:, credential_id:)
      raise ArgumentError, "unknown credential type" unless CREDENTIAL_TYPES.include?(credential_type)

      token = SecureRandom.urlsafe_base64(TOKEN_BYTES)
      expires_at = TOKEN_TTL.from_now
      written = Rails.cache.write(
        cache_key(token),
        {
          "user_id" => user.id,
          "path" => path,
          "credential_type" => credential_type,
          "credential_id" => credential_id,
          "expires_at" => expires_at.iso8601
        },
        expires_in: TOKEN_TTL,
        unless_exist: true
      )
      raise "web handoff token could not be stored" unless written

      [ token, expires_at ]
    end

    # Consumes the token and returns its Grant, or nil when it is unknown, used or expired. Only the
    # request whose delete actually removes the entry may proceed, the same claim the desktop SSO
    # exchange uses, so two concurrent redemptions can't both succeed.
    def redeem(token)
      return unless token.is_a?(String) && token.present? && token.bytesize <= 256

      key = cache_key(token)
      data = Rails.cache.read(key)
      claimed = Rails.cache.delete(key)
      return unless data.is_a?(Hash) && claimed

      expires_at = Time.zone.parse(data["expires_at"].to_s)
      return if expires_at.nil? || expires_at <= Time.current

      Grant.new(
        user_id: data["user_id"],
        path: data["path"],
        credential_type: data["credential_type"],
        credential_id: data["credential_id"]
      )
    rescue ArgumentError
      nil
    end

    # The credential that minted a handoff must still be live, belong to the user and allow writes.
    def credential_active?(user:, credential_type:, credential_id:)
      return false if user.nil? || credential_id.blank?

      case credential_type
      when "api_key"
        key = ApiKey.active.find_by(id: credential_id, user_id: user.id)
        key.present? && Array(key.scopes).include?("read_write")
      when "oauth"
        token = Doorkeeper::AccessToken.find_by(id: credential_id)
        token.present? && token.accessible? && token.resource_owner_id == user.id &&
          token.scopes.include?("read_write")
      else
        false
      end
    end

    def app_callback_url(status)
      APP_CALLBACK_URLS.fetch(status.to_s, APP_CALLBACK_URLS.fetch("ok"))
    end

    private
      def cache_key(token)
        "#{CACHE_PREFIX}#{Digest::SHA256.hexdigest(token)}"
      end
  end
end
