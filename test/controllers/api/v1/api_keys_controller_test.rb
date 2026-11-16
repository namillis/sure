# frozen_string_literal: true

require "test_helper"

class Api::V1::ApiKeysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @user.api_keys.destroy_all

    @write_key = create_api_key(@user, "read_write")
    @read_key = create_api_key(@user, "read")
  end

  teardown do
    ApiKey.where(user: [ @user, users(:family_member), family_guest ]).find_each do |key|
      Redis.new.del("api_rate_limit:#{key.id}")
    end
  end

  test "index lists the user's active keys masked, newest first" do
    revoked = create_api_key(@user, "read")
    revoked.revoke!
    other_user_key = create_api_key(users(:family_member), "read")

    get api_v1_api_keys_url, headers: json_headers(@read_key)

    assert_response :success
    keys = JSON.parse(response.body)["data"]
    assert_equal [ @read_key.id, @write_key.id ], keys.map { |key| key["id"] }
    assert_not_includes keys.map { |key| key["id"] }, revoked.id
    assert_not_includes keys.map { |key| key["id"] }, other_user_key.id

    listed = keys.first
    assert_equal [ "read" ], listed["scopes"]
    assert_equal "********#{@read_key.plain_key.last(4)}", listed["display_key"]
    assert listed["current"]
    assert_not keys.second["current"]
    assert_not listed.key?("plain_key")
    assert_not_includes response.body, @read_key.plain_key
    assert_not_includes response.body, @write_key.plain_key
  end

  test "index hides the demo monitoring key" do
    ApiKey.create!(user: @user, name: "Demo monitoring", scopes: [ "read" ], source: "monitoring",
      display_key: ApiKey::DEMO_MONITORING_KEY)

    get api_v1_api_keys_url, headers: json_headers(@read_key)

    assert_response :success
    assert_equal 2, JSON.parse(response.body)["data"].size
  end

  test "create returns the full key once and the list never does" do
    assert_difference -> { @user.api_keys.count }, 1 do
      assert_difference -> { SecurityAuditLog.where(event_type: "api_key_created").count }, 1 do
        post api_v1_api_keys_url, params: { api_key: { name: "Shortcuts", scopes: [ "read" ] } }.to_json,
          headers: json_headers(@write_key)
      end
    end

    assert_response :created
    created = JSON.parse(response.body)["data"]
    key = @user.api_keys.find(created["id"])
    assert_equal key.plain_key, created["plain_key"]
    assert_equal 64, created["plain_key"].length
    assert_equal [ "read" ], key.scopes
    assert_equal "web", key.source
    assert_equal "Shortcuts", created["name"]
    assert_not created["current"]

    get api_v1_api_keys_url, headers: json_headers(@write_key)

    assert_not_includes response.body, created["plain_key"]
  end

  test "create accepts a scope string the way the web form sends it" do
    post api_v1_api_keys_url, params: { api_key: { name: "Writer", scopes: "read_write" } }.to_json,
      headers: json_headers(@write_key)

    assert_response :created
    assert_equal [ "read_write" ], JSON.parse(response.body)["data"]["scopes"]
  end

  test "create works with an OAuth token that has read_write" do
    token = oauth_token("read_write")

    post api_v1_api_keys_url, params: { api_key: { name: "From OAuth", scopes: [ "read_write" ] } }.to_json,
      headers: { "Authorization" => "Bearer #{token.token}", "Content-Type" => "application/json" }

    assert_response :created
  end

  test "a read credential cannot create a key, so no key gets more scope than the one creating it" do
    assert_no_difference -> { ApiKey.count } do
      post api_v1_api_keys_url, params: { api_key: { name: "Escalate", scopes: [ "read_write" ] } }.to_json,
        headers: json_headers(@read_key)
      assert_response :forbidden
      assert_equal "insufficient_scope", JSON.parse(response.body)["error"]

      post api_v1_api_keys_url, params: { api_key: { name: "Escalate", scopes: [ "read" ] } }.to_json,
        headers: { "Authorization" => "Bearer #{oauth_token("read").token}", "Content-Type" => "application/json" }
      assert_response :forbidden
    end
  end

  test "create rejects invalid scopes and a taken name" do
    post api_v1_api_keys_url, params: { api_key: { name: "Bad", scopes: [ "admin" ] } }.to_json,
      headers: json_headers(@write_key)
    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "validation_failed", body["error"]
    assert_includes body["errors"].join, "read_write"

    post api_v1_api_keys_url, params: { api_key: { name: "Two", scopes: %w[read read_write] } }.to_json,
      headers: json_headers(@write_key)
    assert_response :unprocessable_entity

    post api_v1_api_keys_url, params: { api_key: { name: @read_key.name, scopes: [ "read" ] } }.to_json,
      headers: json_headers(@write_key)
    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"].join, "taken"
  end

  test "create requires an api_key body" do
    post api_v1_api_keys_url, params: {}.to_json, headers: json_headers(@write_key)

    assert_response :bad_request
  end

  test "create ignores a requested source" do
    post api_v1_api_keys_url, params: { api_key: { name: "Sneaky", scopes: [ "read" ], source: "monitoring" } }.to_json,
      headers: json_headers(@write_key)

    assert_response :created
    assert_equal "web", ApiKey.find(JSON.parse(response.body)["data"]["id"]).source
  end

  test "create keeps no key when the audit log cannot be written" do
    SecurityAuditLog.stubs(:log_api_key_created!).raises(ActiveRecord::ActiveRecordError, "audit down")

    assert_no_difference -> { ApiKey.count } do
      post api_v1_api_keys_url, params: { api_key: { name: "Unaudited", scopes: [ "read" ] } }.to_json,
        headers: json_headers(@write_key)
    end

    assert_response :unprocessable_entity
    assert_equal "creation_failed", JSON.parse(response.body)["error"]
  end

  test "create is rate limited per user" do
    # The test cache is a null store, so hand out the count a real store would.
    Api::V1::ApiKeysController.cache_store.stubs(:increment).returns(Api::V1::ApiKeysController::CREATE_LIMIT + 1)

    assert_no_difference -> { ApiKey.count } do
      post api_v1_api_keys_url, params: { api_key: { name: "One too many", scopes: [ "read" ] } }.to_json,
        headers: json_headers(@write_key)
    end

    assert_response :too_many_requests
    assert_equal "rate_limit_exceeded", JSON.parse(response.body)["error"]
  end

  test "guests manage their own keys like on the web" do
    guest_key = create_api_key(family_guest, "read_write")

    post api_v1_api_keys_url, params: { api_key: { name: "Guest second", scopes: [ "read" ] } }.to_json,
      headers: json_headers(guest_key)

    assert_response :created
    assert_equal family_guest.id, ApiKey.find(JSON.parse(response.body)["data"]["id"]).user_id
  end

  test "destroy revokes another of the user's keys" do
    assert_difference -> { SecurityAuditLog.where(event_type: "api_key_revoked").count }, 1 do
      delete api_v1_api_key_url(@read_key), headers: json_headers(@write_key)
    end

    assert_response :no_content
    assert @read_key.reload.revoked?
  end

  test "destroy refuses the key authenticating the request" do
    delete api_v1_api_key_url(@write_key), headers: json_headers(@write_key)

    assert_response :unprocessable_entity
    assert_equal "cannot_revoke_current_key", JSON.parse(response.body)["error"]
    assert_not @write_key.reload.revoked?
  end

  test "destroy with an OAuth token can revoke any of the user's keys" do
    delete api_v1_api_key_url(@write_key),
      headers: { "Authorization" => "Bearer #{oauth_token("read_write").token}" }

    assert_response :no_content
    assert @write_key.reload.revoked?
  end

  test "destroy needs read_write" do
    delete api_v1_api_key_url(@write_key), headers: json_headers(@read_key)

    assert_response :forbidden
    assert_not @write_key.reload.revoked?
  end

  test "destroy 404s another user's key, a revoked key, the demo key and a bad id" do
    other_user_key = create_api_key(users(:family_member), "read")
    revoked = create_api_key(@user, "read").tap(&:revoke!)
    demo = ApiKey.create!(user: @user, name: "Demo monitoring", scopes: [ "read" ], source: "monitoring",
      display_key: ApiKey::DEMO_MONITORING_KEY)

    [ other_user_key.id, revoked.id, demo.id, "not-a-uuid" ].each do |id|
      delete api_v1_api_key_url(id), headers: json_headers(@write_key)
      assert_response :not_found
    end

    assert_not other_user_key.reload.revoked?
    assert_not demo.reload.revoked?
  end

  test "requires authentication" do
    get api_v1_api_keys_url
    assert_response :unauthorized

    post api_v1_api_keys_url, params: { api_key: { name: "x", scopes: [ "read" ] } }.to_json,
      headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized

    delete api_v1_api_key_url(@read_key)
    assert_response :unauthorized
  end

  private
    def create_api_key(user, scope)
      ApiKey.create!(
        user: user,
        name: "Keys #{scope} #{SecureRandom.hex(4)}",
        scopes: [ scope ],
        source: "web",
        display_key: "test_#{scope}_#{SecureRandom.hex(8)}"
      )
    end

    def oauth_token(scopes)
      application = Doorkeeper::Application.create!(name: "Keys test app", redirect_uri: "https://example.com/callback",
        scopes: "read read_write")
      Doorkeeper::AccessToken.create!(application: application, resource_owner_id: @user.id, scopes: scopes)
    end

    def json_headers(api_key)
      { "X-Api-Key" => api_key.plain_key, "Content-Type" => "application/json" }
    end
end
