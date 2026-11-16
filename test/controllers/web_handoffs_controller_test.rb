require "test_helper"

class WebHandoffsControllerTest < ActionDispatch::IntegrationTest
  APP_DONE_OK = "sureplus://connections/done?status=ok"

  setup do
    ensure_tailwind_build
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    @user = users(:family_admin)
    @api_key = create_api_key(@user)
  end

  teardown do
    ApiKey.where(user: [ @user, users(:family_member) ]).find_each { |key| Redis.new.del("api_rate_limit:#{key.id}") }
  end

  test "redeeming opens a flagged, short-lived session for the API user on the requested page" do
    token = issue_token("/settings/providers")

    assert_difference -> { @user.sessions.count }, 1 do
      get redeem_web_handoff_url(token: token)
    end

    assert_redirected_to "/settings/providers"
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    record = @user.sessions.order(:created_at).last
    handoff = record.data[Session::WEB_HANDOFF_KEY]
    assert_equal "/settings/providers", handoff["started_path"]
    assert_equal [ "api_key", @api_key.id ], [ handoff["credential_type"], handoff["credential_id"] ]
    assert_in_delta 30.minutes.from_now, Time.iso8601(handoff["expires_at"]), 5
    assert_match(/expires=/i, response.headers["Set-Cookie"].to_s)

    get settings_providers_url
    assert_response :success
  end

  test "an MFA user is not asked for a code: the handoff satisfies MFA" do
    @user.update_columns(otp_secret: ROTP::Base32.random(32), otp_required: true)

    get redeem_web_handoff_url(token: issue_token("/settings/providers"))

    assert_redirected_to "/settings/providers"
    get settings_providers_url
    assert_response :success
  end

  test "a token works once" do
    token = issue_token("/settings/providers")

    get redeem_web_handoff_url(token: token)
    assert_redirected_to "/settings/providers"

    reset!
    assert_no_difference -> { Session.count } do
      get redeem_web_handoff_url(token: token)
    end
    assert_redirected_to new_session_path
  end

  test "an expired token goes to sign-in" do
    token = issue_token("/settings/providers")

    travel 61.seconds do
      assert_no_difference -> { Session.count } do
        get redeem_web_handoff_url(token: token)
      end
    end

    assert_redirected_to new_session_path
  end

  test "an unknown token goes to sign-in without echoing it" do
    get redeem_web_handoff_url(token: "made-up-token-value")

    assert_redirected_to new_session_path
    follow_redirect!
    assert_not_includes response.body, "made-up-token-value"
  end

  test "a token whose API key was revoked before redemption goes to sign-in" do
    token = issue_token("/settings/providers")
    @api_key.revoke!

    get redeem_web_handoff_url(token: token)

    assert_redirected_to new_session_path
  end

  test "the token never reaches the logs" do
    token = issue_token("/settings/providers")
    log = StringIO.new
    capture = ActiveSupport::Logger.new(log)
    capture.level = Logger::DEBUG
    Rails.logger.broadcast_to(capture)

    begin
      get redeem_web_handoff_url(token: token)
    ensure
      Rails.logger.stop_broadcasting_to(capture)
    end

    assert_redirected_to "/settings/providers"
    assert_includes log.string, "/web_handoffs/redeem?token=[FILTERED]"
    assert_not_includes log.string, token
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    assert_equal "[FILTERED]", filter.filter("token" => token)["token"]
  end

  test "a handoff session can't reach security, keys, password, MFA, imports, exports, profile or admin pages" do
    [
      "/settings/security", "/settings/api_keys", "/settings/api_keys/new", "/password/edit", "/mfa/new",
      "/imports", "/family_exports", "/settings/profile", "/settings/hosting", "/admin/users", "/transactions"
    ].each do |path|
      start_handoff("/settings/providers")
      handoff_session = @user.sessions.order(:created_at).last

      get path

      assert_redirected_to web_handoff_done_path(status: "ok"), path
      assert_not Session.exists?(handoff_session.id), path
      get path
      assert_redirected_to new_session_url, path
    end
  end

  test "a handoff session can't change protected settings by form or fetch" do
    start_handoff("/settings/providers")
    original_digest = @user.password_digest

    patch password_url, params: { user: { password: "NewPassword1!", password_confirmation: "NewPassword1!" } }
    assert_response :forbidden
    patch settings_providers_url, params: { setting: { plaid_client_id: "x" } }
    assert_response :forbidden
    post settings_api_keys_url, params: { api_key: { name: "sneaky", scopes: "read_write" } }
    assert_response :forbidden

    assert_equal original_digest, @user.reload.password_digest
    assert_not @user.api_keys.exists?(name: "sneaky")
    get settings_providers_url
    assert_response :success
  end

  test "frames, prefetches and background fetches elsewhere are refused without ending the flow" do
    start_handoff("/settings/providers")

    get "/settings/security", headers: { "Turbo-Frame" => "modal" }
    assert_response :forbidden
    get "/transactions", headers: { "X-Sec-Purpose" => "prefetch" }
    assert_response :forbidden
    get "/transactions", headers: { "Sec-Fetch-Mode" => "cors" }
    assert_response :forbidden

    get settings_providers_url
    assert_response :success
  end

  test "a handoff session can't authorize an OAuth app or reach admin-only mounts" do
    start_handoff("/settings/providers")
    oauth_app = Doorkeeper::Application.create!(name: "Third party", redirect_uri: "https://example.com/callback",
      scopes: "read read_write")

    get "/oauth/authorize", params: { client_id: oauth_app.uid, redirect_uri: "https://example.com/callback",
      response_type: "code", scope: "read_write" }

    assert_redirected_to new_session_url
    assert_equal 0, Doorkeeper::AccessGrant.where(application: oauth_app).count
  end

  test "the session expires after 30 minutes" do
    start_handoff("/settings/providers")
    handoff_session = @user.sessions.order(:created_at).last

    travel 31.minutes do
      get settings_providers_url

      assert_redirected_to new_session_url
      # The browser drops the cookie at 30 minutes; the server refuses the session regardless.
      assert handoff_session.reload.expired?
      assert_nil Session.find_active_by_cookie(handoff_session.id, allow_web_handoff: true)
    end
  end

  test "revoking the minting API key ends the flow" do
    start_handoff("/settings/providers")
    @api_key.revoke!

    get settings_providers_url

    assert_redirected_to web_handoff_done_path(status: "error")
  end

  test "finishing a SimpleFIN setup sends the browser back to the app and ends the session" do
    item = SimplefinItem.create!(family: @user.family, name: "Handoff bank", access_url: "https://example.com/access")
    simplefin_account = item.simplefin_accounts.create!(name: "Checking", account_id: "sf_handoff_1", currency: "USD",
      current_balance: 10, account_type: "depository")
    start_handoff("/simplefin_items/#{item.id}/setup_accounts")
    handoff_session = @user.sessions.order(:created_at).last

    get setup_accounts_simplefin_item_url(item)
    assert_response :success

    post complete_account_setup_simplefin_item_url(item), params: { account_types: { simplefin_account.id => "Depository" },
      account_subtypes: { simplefin_account.id => "checking" } }

    assert_redirected_to web_handoff_done_path(status: "ok")
    assert_not Session.exists?(handoff_session.id)
    assert simplefin_account.reload.account.present?

    follow_redirect!
    assert_redirected_to APP_DONE_OK
  end

  test "following a flow's Cancel link reports cancelled" do
    item = SimplefinItem.create!(family: @user.family, name: "Handoff bank", access_url: "https://example.com/access")
    start_handoff("/simplefin_items/#{item.id}/setup_accounts")

    get accounts_url, headers: { "Referer" => setup_accounts_simplefin_item_url(item) }

    assert_redirected_to web_handoff_done_path(status: "cancelled")
  end

  test "a redirect the web makes with an alert reports an error" do
    member = users(:family_member)
    member_key = create_api_key(member)

    start_handoff("/settings/providers", api_key: member_key)
    get settings_providers_url

    # Members can't open the providers page; the web sends them home with an alert.
    assert_redirected_to web_handoff_done_path(status: "error")
  end

  test "done redirects a real navigation to the app and gives Turbo a page to reload" do
    get web_handoff_done_url(status: "cancelled")
    assert_redirected_to "sureplus://connections/done?status=cancelled"

    get web_handoff_done_url(status: "ok"), headers: { "Sec-Fetch-Mode" => "navigate" }
    assert_redirected_to APP_DONE_OK

    get web_handoff_done_url(status: "ok"), headers: { "Sec-Fetch-Mode" => "cors", "X-Turbo-Request-Id" => "1" }
    assert_response :success
    assert_includes response.body, %(<meta name="turbo-visit-control" content="reload">)
    assert_includes response.body, APP_DONE_OK

    get web_handoff_done_url(status: "javascript:alert(1)")
    assert_redirected_to APP_DONE_OK
  end

  test "ordinary web sessions are unaffected" do
    sign_in @user

    get settings_security_url
    assert_response :success
  end

  private
    def create_api_key(user)
      ApiKey.create!(user: user, name: "Handoff web #{SecureRandom.hex(4)}", scopes: [ "read_write" ], source: "web",
        display_key: "test_handoff_web_#{SecureRandom.hex(8)}")
    end

    def issue_token(path, api_key: @api_key)
      post api_v1_web_handoffs_url, params: { web_handoff: { path: path } }.to_json,
        headers: { "X-Api-Key" => api_key.plain_key, "Content-Type" => "application/json" }
      assert_response :created
      Rack::Utils.parse_query(URI.parse(JSON.parse(response.body)["url"]).query)["token"]
    end

    def start_handoff(path, api_key: @api_key)
      reset!
      get redeem_web_handoff_url(token: issue_token(path, api_key: api_key))
      assert_redirected_to path
    end
end
