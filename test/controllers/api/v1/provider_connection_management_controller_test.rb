# frozen_string_literal: true

require "test_helper"

class Api::V1::ProviderConnectionManagementControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:family_admin)
    @member = users(:family_member)
    @family = @admin.family
    @plaid_item = plaid_items(:one)
    @mercury_item = mercury_items(:one)

    @admin.api_keys.active.destroy_all
    @member.api_keys.active.destroy_all

    @admin_key = create_key(@admin, [ "read_write" ])
    @read_key = create_key(@admin, [ "read" ])
    @member_key = create_key(@member, [ "read_write" ])
  end

  test "queues a Plaid sync with a provider refresh" do
    PlaidItem.any_instance.expects(:request_transactions_refresh_later).once

    assert_difference -> { @plaid_item.syncs.count }, 1 do
      post sync_api_v1_provider_connection_url(@plaid_item, provider: "plaid"), headers: api_headers(@admin_key)
    end

    assert_response :accepted
    json = JSON.parse(response.body)
    assert_equal @plaid_item.id, json["id"]
    assert_equal "plaid", json["provider"]
    assert_equal "PlaidItem", json["provider_type"]
    assert_equal true, json["sync"]["syncing"]
  end

  test "member may sync and disconnect a Plaid connection they own" do
    @plaid_item.update!(owner: @member)
    PlaidItem.any_instance.stubs(:request_transactions_refresh_later)

    post sync_api_v1_provider_connection_url(@plaid_item, provider: "plaid"), headers: api_headers(@member_key)
    assert_response :accepted

    delete api_v1_provider_connection_url(@plaid_item, provider: "plaid"), headers: api_headers(@member_key)
    assert_response :accepted
    assert @plaid_item.reload.scheduled_for_deletion?
  end

  test "member may not manage a Plaid connection someone else owns" do
    @plaid_item.update!(owner: @admin)

    assert_no_difference -> { @plaid_item.syncs.count } do
      post sync_api_v1_provider_connection_url(@plaid_item, provider: "plaid"), headers: api_headers(@member_key)
    end
    assert_response :forbidden
    assert_equal "forbidden", JSON.parse(response.body)["error"]

    delete api_v1_provider_connection_url(@plaid_item, provider: "plaid"), headers: api_headers(@member_key)
    assert_response :forbidden
    assert_not @plaid_item.reload.scheduled_for_deletion?
  end

  test "disconnects a Plaid connection in the background" do
    assert_enqueued_with(job: DestroyJob) do
      delete api_v1_provider_connection_url(@plaid_item, provider: "plaid"), headers: api_headers(@admin_key)
    end

    assert_response :accepted
    json = JSON.parse(response.body)
    assert_equal @plaid_item.id, json["id"]
    assert_equal true, json["scheduled_for_deletion"]
    assert @plaid_item.reload.scheduled_for_deletion?
  end

  test "queues a Mercury sync" do
    assert_difference -> { @mercury_item.syncs.count }, 1 do
      post sync_api_v1_provider_connection_url(@mercury_item, provider: "mercury"), headers: api_headers(@admin_key)
    end

    assert_response :accepted
    json = JSON.parse(response.body)
    assert_equal "mercury", json["provider"]
    assert_equal true, json["sync"]["syncing"]
  end

  test "does not queue a second sync while one is running" do
    running = @mercury_item.syncs.create!(status: "syncing", syncing_at: Time.current)

    assert_no_difference -> { Sync.count } do
      post sync_api_v1_provider_connection_url(@mercury_item, provider: "mercury"), headers: api_headers(@admin_key)
    end

    assert_response :accepted
    json = JSON.parse(response.body)
    assert_equal true, json["sync"]["syncing"]
    assert_equal running.id, json["sync"]["latest"]["id"]
  end

  test "disconnects a Mercury connection after unlinking its accounts" do
    MercuryItem.any_instance.expects(:unlink_all!).with(dry_run: false).returns([])

    assert_enqueued_with(job: DestroyJob) do
      delete api_v1_provider_connection_url(@mercury_item, provider: "mercury"), headers: api_headers(@admin_key)
    end

    assert_response :accepted
    assert_equal true, JSON.parse(response.body)["scheduled_for_deletion"]
    assert @mercury_item.reload.scheduled_for_deletion?
  end

  test "only an admin may manage a non-Plaid connection" do
    post sync_api_v1_provider_connection_url(@mercury_item, provider: "mercury"), headers: api_headers(@member_key)
    assert_response :forbidden

    delete api_v1_provider_connection_url(@mercury_item, provider: "mercury"), headers: api_headers(@member_key)
    assert_response :forbidden
    assert_not @mercury_item.reload.scheduled_for_deletion?
  end

  test "keeps a Trade Republic connection when its accounts fail to unlink" do
    item = trade_republic_items(:configured_item)
    TradeRepublicItem.any_instance.stubs(:unlink_all!).returns([ { provider_account_id: "x", error: "boom" } ])

    assert_no_enqueued_jobs(only: DestroyJob) do
      delete api_v1_provider_connection_url(item, provider: "trade_republic"), headers: api_headers(@admin_key)
    end

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal "unlink_failed", json["error"]
    assert_equal [ json["message"] ], json["errors"]
    assert_not item.reload.scheduled_for_deletion?
  end

  test "rejects a sync of a Trade Republic connection that needs a new login" do
    item = trade_republic_items(:configured_item)
    TradeRepublicItem.any_instance.stubs(:ready_for_sync?).returns(false)

    assert_no_difference -> { item.syncs.count } do
      post sync_api_v1_provider_connection_url(item, provider: "trade_republic"), headers: api_headers(@admin_key)
    end

    assert_response :unprocessable_entity
    assert_equal "reconnect_required", JSON.parse(response.body)["error"]
  end

  test "returns not found for an unknown, malformed or other family's connection" do
    post sync_api_v1_provider_connection_url(SecureRandom.uuid), headers: api_headers(@admin_key)
    assert_response :not_found
    assert_equal "record_not_found", JSON.parse(response.body)["error"]

    delete api_v1_provider_connection_url("not-a-uuid"), headers: api_headers(@admin_key)
    assert_response :not_found

    other_item = families(:empty).plaid_items.create!(name: "Other Bank", plaid_id: "item_other", access_token: "token_other")
    delete api_v1_provider_connection_url(other_item, provider: "plaid"), headers: api_headers(@admin_key)
    assert_response :not_found
    assert_not other_item.reload.scheduled_for_deletion?
  end

  test "asks for the provider when two connections share an id" do
    shared_id = @plaid_item.id
    @mercury_item.update_column(:id, shared_id) unless @mercury_item.id == shared_id

    delete api_v1_provider_connection_url(shared_id), headers: api_headers(@admin_key)

    assert_response :unprocessable_entity
    assert_equal "ambiguous_connection", JSON.parse(response.body)["error"]
    assert_not @plaid_item.reload.scheduled_for_deletion?
  end

  test "returns not found for an unknown provider" do
    post sync_api_v1_provider_connection_url(@plaid_item, provider: "nope"), headers: api_headers(@admin_key)
    assert_response :not_found
  end

  test "requires authentication" do
    post sync_api_v1_provider_connection_url(@plaid_item, provider: "plaid")
    assert_response :unauthorized

    delete api_v1_provider_connection_url(@plaid_item, provider: "plaid")
    assert_response :unauthorized
  end

  test "rejects read-only keys" do
    post sync_api_v1_provider_connection_url(@plaid_item, provider: "plaid"), headers: api_headers(@read_key)
    assert_response :forbidden
    assert_equal "insufficient_scope", JSON.parse(response.body)["error"]

    delete api_v1_provider_connection_url(@plaid_item, provider: "plaid"), headers: api_headers(@read_key)
    assert_response :forbidden
    assert_not @plaid_item.reload.scheduled_for_deletion?
  end

  test "rejects guests" do
    @member.update_column(:role, "guest")
    @plaid_item.update_column(:owner_id, @member.id)

    delete api_v1_provider_connection_url(@plaid_item, provider: "plaid"), headers: api_headers(@member_key)
    assert_response :forbidden
    assert_not @plaid_item.reload.scheduled_for_deletion?
  end

  private

    def create_key(user, scopes)
      key = ApiKey.create!(
        user: user,
        name: "Test #{scopes.join} key",
        scopes: scopes,
        display_key: "test_#{SecureRandom.hex(8)}",
        source: scopes == [ "read" ] ? "web" : "mobile"
      )
      Redis.new.del("api_rate_limit:#{key.id}")
      key
    end

    def api_headers(api_key)
      { "X-Api-Key" => api_key.plain_key }
    end
end
