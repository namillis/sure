# frozen_string_literal: true

require "test_helper"

class Api::V1::WebHandoffsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @user.api_keys.destroy_all
    @write_key = create_api_key(@user, "read_write")
    @read_key = create_api_key(@user, "read")
    @cache = ActiveSupport::Cache::MemoryStore.new
    Rails.stubs(:cache).returns(@cache)
  end

  teardown do
    ApiKey.where(user: [ @user, family_guest ]).find_each { |key| Redis.new.del("api_rate_limit:#{key.id}") }
  end

  test "create returns a one-time redeem URL for an allowed path" do
    post api_v1_web_handoffs_url, params: { web_handoff: { path: "/plaid_items/new?region=us" } }.to_json,
      headers: json_headers(@write_key)

    assert_response :created
    body = JSON.parse(response.body)
    uri = URI.parse(body["url"])
    assert_equal "/web_handoffs/redeem", uri.path
    token = Rack::Utils.parse_query(uri.query)["token"]
    assert_operator token.bytesize, :>=, 43
    assert_in_delta 60.seconds.from_now, Time.iso8601(body["expires_at"]), 2

    grant = WebHandoff.redeem(token)
    assert_equal [ @user.id, "/plaid_items/new?region=us", "api_key", @write_key.id ],
      [ grant.user_id, grant.path, grant.credential_type, grant.credential_id ]
  end

  test "create accepts a read_write OAuth token and binds the handoff to it" do
    access_token = oauth_token("read_write")

    post api_v1_web_handoffs_url, params: { web_handoff: { path: "/settings/providers" } }.to_json,
      headers: { "Authorization" => "Bearer #{access_token.token}", "Content-Type" => "application/json" }

    assert_response :created
    token = Rack::Utils.parse_query(URI.parse(JSON.parse(response.body)["url"]).query)["token"]
    grant = WebHandoff.redeem(token)
    assert_equal [ "oauth", access_token.id ], [ grant.credential_type, grant.credential_id ]
  end

  test "create requires authentication" do
    post api_v1_web_handoffs_url, params: { web_handoff: { path: "/settings/providers" } }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
  end

  test "create requires the read_write scope" do
    post api_v1_web_handoffs_url, params: { web_handoff: { path: "/settings/providers" } }.to_json,
      headers: json_headers(@read_key)
    assert_response :forbidden
    assert_equal "insufficient_scope", JSON.parse(response.body)["error"]

    post api_v1_web_handoffs_url, params: { web_handoff: { path: "/settings/providers" } }.to_json,
      headers: { "Authorization" => "Bearer #{oauth_token('read').token}", "Content-Type" => "application/json" }
    assert_response :forbidden
  end

  test "guests can't open a connect flow" do
    post api_v1_web_handoffs_url, params: { web_handoff: { path: "/settings/providers" } }.to_json,
      headers: json_headers(create_api_key(family_guest, "read_write"))

    assert_response :forbidden
    assert_equal "forbidden", JSON.parse(response.body)["error"]
  end

  test "create rejects paths outside the connect flows" do
    [
      "/settings/security", "/settings/api_keys", "/password/edit", "https://evil.example/settings/providers",
      "//evil.example/settings/providers", "/\\evil.example/plaid_items/new", "/plaid_items/new.json", "/accounts",
      "settings/providers", ""
    ].each do |path|
      post api_v1_web_handoffs_url, params: { web_handoff: { path: path } }.to_json, headers: json_headers(@write_key)

      assert_response :unprocessable_entity, path
      body = JSON.parse(response.body)
      assert_equal "path_not_allowed", body["error"]
      assert_equal [ body["message"] ], body["errors"]
    end

    post api_v1_web_handoffs_url, params: { web_handoff: { path: { nested: "x" } } }.to_json, headers: json_headers(@write_key)
    assert_response :unprocessable_entity
    assert_empty @cache.instance_variable_get(:@data)
  end

  test "create requires a web_handoff body" do
    post api_v1_web_handoffs_url, params: {}.to_json, headers: json_headers(@write_key)

    assert_response :bad_request
  end

  test "create is rate limited per user" do
    # The rate limiter needs a counting store; hand out the count a real store would.
    Api::V1::WebHandoffsController.cache_store.stubs(:increment).returns(Api::V1::WebHandoffsController::CREATE_LIMIT + 1)

    post api_v1_web_handoffs_url, params: { web_handoff: { path: "/settings/providers" } }.to_json,
      headers: json_headers(@write_key)

    assert_response :too_many_requests
    assert_equal "rate_limit_exceeded", JSON.parse(response.body)["error"]
  end

  private
    def create_api_key(user, scope)
      ApiKey.create!(user: user, name: "Handoff #{scope} #{SecureRandom.hex(4)}", scopes: [ scope ], source: "web",
        display_key: "test_handoff_#{scope}_#{SecureRandom.hex(8)}")
    end

    def oauth_token(scopes)
      application = Doorkeeper::Application.create!(name: "Handoff test app", redirect_uri: "https://example.com/callback",
        scopes: "read read_write")
      Doorkeeper::AccessToken.create!(application: application, resource_owner_id: @user.id, scopes: scopes)
    end

    def json_headers(api_key)
      { "X-Api-Key" => api_key.plain_key, "Content-Type" => "application/json" }
    end
end
