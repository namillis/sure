require "test_helper"

class WebHandoffTest < ActiveSupport::TestCase
  setup do
    @cache = ActiveSupport::Cache::MemoryStore.new
    Rails.stubs(:cache).returns(@cache)
    @user = users(:family_admin)
    @api_key = ApiKey.create!(user: @user, name: "Handoff model #{SecureRandom.hex(4)}", scopes: [ "read_write" ],
      source: "web", display_key: "test_handoff_#{SecureRandom.hex(8)}")
  end

  test "stores only a digest of the token and redeems it once" do
    token, expires_at = issue

    assert_operator token.bytesize, :>=, 43
    assert_in_delta 60.seconds.from_now, expires_at, 2
    keys = @cache.instance_variable_get(:@data).keys
    assert_equal [ "sure_plus:web_handoff:#{Digest::SHA256.hexdigest(token)}" ], keys
    assert_not keys.any? { |key| key.include?(token) }

    grant = WebHandoff.redeem(token)
    assert_equal @user.id, grant.user_id
    assert_equal "/settings/providers", grant.path
    assert_equal [ "api_key", @api_key.id ], [ grant.credential_type, grant.credential_id ]
    assert_nil WebHandoff.redeem(token)
  end

  test "an expired token can't be redeemed" do
    token, = issue

    travel 61.seconds do
      assert_nil WebHandoff.redeem(token)
    end
  end

  test "unknown or malformed tokens redeem to nil" do
    assert_nil WebHandoff.redeem("nope")
    assert_nil WebHandoff.redeem(nil)
    assert_nil WebHandoff.redeem([ "x" ])
  end

  test "the minting credential must stay live, owned and read_write" do
    assert WebHandoff.credential_active?(user: @user, credential_type: "api_key", credential_id: @api_key.id)
    assert_not WebHandoff.credential_active?(user: users(:family_member), credential_type: "api_key", credential_id: @api_key.id)
    assert_not WebHandoff.credential_active?(user: @user, credential_type: "other", credential_id: @api_key.id)

    @api_key.update!(scopes: [ "read" ])
    assert_not WebHandoff.credential_active?(user: @user, credential_type: "api_key", credential_id: @api_key.id)

    @api_key.update!(scopes: [ "read_write" ])
    @api_key.revoke!
    assert_not WebHandoff.credential_active?(user: @user, credential_type: "api_key", credential_id: @api_key.id)
  end

  test "an OAuth token must be accessible, owned and read_write" do
    application = Doorkeeper::Application.create!(name: "Handoff app", redirect_uri: "https://example.com/callback",
      scopes: "read read_write")
    token = Doorkeeper::AccessToken.create!(application: application, resource_owner_id: @user.id, scopes: "read_write")
    read_token = Doorkeeper::AccessToken.create!(application: application, resource_owner_id: @user.id, scopes: "read")

    assert WebHandoff.credential_active?(user: @user, credential_type: "oauth", credential_id: token.id)
    assert_not WebHandoff.credential_active?(user: @user, credential_type: "oauth", credential_id: read_token.id)

    token.revoke
    assert_not WebHandoff.credential_active?(user: @user, credential_type: "oauth", credential_id: token.id)
  end

  test "entry paths are matched on recognized provider routes" do
    item_id = SecureRandom.uuid
    allowed = [
      "/settings/providers",
      "/settings/providers/simplefin/connect_form",
      "/plaid_items/new?region=us&accountable_type=Depository",
      "/plaid_items/#{item_id}/edit",
      "/simplefin_items/#{item_id}/setup_accounts",
      "/lunchflow_items/select_accounts",
      "/enable_banking_items/new",
      "/enable_banking_items/#{item_id}/select_bank",
      "/brex_items/select_accounts",
      "/onchain_wallet_items/new_wallet"
    ]
    rejected = [
      nil, "", "settings/providers", "https://evil.example/settings/providers", "//evil.example/settings/providers",
      "/\\evil.example", "/settings/providers\\..", "/settings/providers#x", "/settings/security", "/settings/api_keys",
      "/password/edit", "/mfa/new", "/imports", "/family_exports", "/admin/users", "/accounts", "/",
      "/plaid_items/new.json", "/simplefin_items/not-a-uuid/edit", "/settings/providers/x y/connect_form",
      "/plaid_items/#{item_id}", "/simplefin_items/#{item_id}/complete_account_setup", "/nope", "/settings/bank_sync",
      "/settings/providers\n", "/#{'a' * 3000}"
    ]

    allowed.each { |path| assert WebHandoff::RoutePolicy.entry_path_allowed?(path), path }
    rejected.each { |path| assert_not WebHandoff::RoutePolicy.entry_path_allowed?(path), path.inspect }
  end

  test "a handoff session reaches only the providers page and provider controllers" do
    policy = WebHandoff::RoutePolicy

    assert policy.session_request_allowed?("settings/providers", "show")
    assert policy.session_request_allowed?("settings/providers", "sync_all")
    assert policy.session_request_allowed?("plaid_items", "create")
    assert policy.session_request_allowed?("enable_banking_items", "callback")
    assert policy.session_request_allowed?("brex_items/account_setups", "complete_account_setup")

    assert_not policy.session_request_allowed?("settings/providers", "update")
    %w[settings/securities settings/api_keys passwords mfa imports family_exports admin/users accounts
       pages users settings/profiles oauth/authorizations].each do |controller|
      assert_not policy.session_request_allowed?(controller, "show"), controller
    end
  end

  test "handoff sessions are only found by callers that enforce them and expire after their lifetime" do
    record = @user.sessions.create!(data: { Session::WEB_HANDOFF_KEY => {
      "expires_at" => Session::WEB_HANDOFF_LIFETIME.from_now.iso8601, "started_path" => "/settings/providers"
    } })

    assert_nil Session.find_active_by_cookie(record.id)
    assert_equal record, Session.find_active_by_cookie(record.id, allow_web_handoff: true)
    assert Session.exists?(record.id)

    travel Session::WEB_HANDOFF_LIFETIME + 1.second do
      assert record.reload.expired?
      assert_nil Session.find_active_by_cookie(record.id, allow_web_handoff: true)
      assert_not Session.exists?(record.id)
    end
  end

  test "ordinary sessions are unaffected" do
    record = @user.sessions.create!

    assert_not record.web_handoff?
    assert_equal record, Session.find_active_by_cookie(record.id)
  end

  test "the app callback only carries a known status" do
    assert_equal "sureplus://connections/done?status=cancelled", WebHandoff.app_callback_url("cancelled")
    assert_equal "sureplus://connections/done?status=ok", WebHandoff.app_callback_url("<script>")
  end

  private
    def issue(path: "/settings/providers")
      WebHandoff.issue!(user: @user, path: path, credential_type: "api_key", credential_id: @api_key.id)
    end
end
