# frozen_string_literal: true

require "test_helper"

class Api::V1::ProviderConnectionSyncSchedulesControllerTest < ActionDispatch::IntegrationTest
  include FinancekitTestHelper

  setup do
    @admin = users(:family_admin)
    @member = users(:family_member)
    @plaid_item = plaid_items(:one)
    @mercury_item = mercury_items(:one)

    [ @admin, @member, family_guest ].each { |user| user.api_keys.active.destroy_all }

    @admin_key = create_key(@admin, "read_write")
    @read_key = create_key(@admin, "read")
    @member_key = create_key(@member, "read_write")
  end

  teardown do
    ApiKey.where(user: [ @admin, @member, family_guest ]).find_each do |key|
      Redis.new.del("api_rate_limit:#{key.id}")
    end
  end

  test "show returns no interval for a connection without a schedule, with the model's intervals" do
    get schedule_url(@plaid_item, "plaid"), headers: api_headers(@read_key)

    assert_response :success
    data = JSON.parse(response.body)["data"]
    assert_equal @plaid_item.id, data["provider_connection_id"]
    assert_equal "plaid", data["provider"]
    assert_nil data["interval_minutes"]
    assert_nil data["next_run_at"]
    assert_equal SyncSchedule::INTERVALS, data["allowed_intervals"]
  end

  test "show returns the saved interval and next run" do
    schedule = @mercury_item.create_sync_schedule!(interval_minutes: 120)

    get schedule_url(@mercury_item, "mercury"), headers: api_headers(@read_key)

    assert_response :success
    data = JSON.parse(response.body)["data"]
    assert_equal "mercury", data["provider"]
    assert_equal 120, data["interval_minutes"]
    assert_equal schedule.next_run_at.iso8601, data["next_run_at"]
  end

  test "update creates and then changes the schedule" do
    assert_difference -> { SyncSchedule.count }, 1 do
      patch schedule_url(@plaid_item, "plaid"), params: { sync_schedule: { interval_minutes: 30 } }.to_json,
        headers: api_headers(@admin_key)
    end
    assert_response :success
    assert_equal 30, JSON.parse(response.body)["data"]["interval_minutes"]

    assert_no_difference -> { SyncSchedule.count } do
      patch schedule_url(@plaid_item, "plaid"), params: { sync_schedule: { interval_minutes: 360 } }.to_json,
        headers: api_headers(@admin_key)
    end
    assert_response :success
    assert_equal 360, @plaid_item.reload.sync_schedule.interval_minutes
  end

  test "update with null removes the schedule" do
    @plaid_item.create_sync_schedule!(interval_minutes: 60)

    assert_difference -> { SyncSchedule.count }, -1 do
      patch schedule_url(@plaid_item, "plaid"), params: { sync_schedule: { interval_minutes: nil } }.to_json,
        headers: api_headers(@admin_key)
    end

    assert_response :success
    assert_nil JSON.parse(response.body)["data"]["interval_minutes"]
  end

  test "update rejects an interval outside the allowed list" do
    @plaid_item.create_sync_schedule!(interval_minutes: 60)

    [ 45, "often" ].each do |interval|
      patch schedule_url(@plaid_item, "plaid"), params: { sync_schedule: { interval_minutes: interval } }.to_json,
        headers: api_headers(@admin_key)

      assert_response :unprocessable_entity
      assert_equal "validation_failed", JSON.parse(response.body)["error"]
    end
    assert_equal 60, @plaid_item.reload.sync_schedule.interval_minutes
  end

  test "update without interval_minutes changes nothing" do
    @plaid_item.create_sync_schedule!(interval_minutes: 60)

    patch schedule_url(@plaid_item, "plaid"), params: { sync_schedule: { other: 1 } }.to_json,
      headers: api_headers(@admin_key)
    assert_response :unprocessable_entity

    patch schedule_url(@plaid_item, "plaid"), params: {}.to_json, headers: api_headers(@admin_key)
    assert_response :bad_request

    assert_equal 60, @plaid_item.reload.sync_schedule.interval_minutes
  end

  test "update needs read_write" do
    patch schedule_url(@plaid_item, "plaid"), params: { sync_schedule: { interval_minutes: 30 } }.to_json,
      headers: api_headers(@read_key)

    assert_response :forbidden
    assert_equal "insufficient_scope", JSON.parse(response.body)["error"]
    assert_nil @plaid_item.reload.sync_schedule
  end

  test "a member manages a Plaid connection they own but not someone else's" do
    @plaid_item.update!(owner: @member)

    patch schedule_url(@plaid_item, "plaid"), params: { sync_schedule: { interval_minutes: 30 } }.to_json,
      headers: api_headers(@member_key)
    assert_response :success

    @plaid_item.update!(owner: @admin)

    get schedule_url(@plaid_item, "plaid"), headers: api_headers(@member_key)
    assert_response :forbidden

    patch schedule_url(@plaid_item, "plaid"), params: { sync_schedule: { interval_minutes: 60 } }.to_json,
      headers: api_headers(@member_key)
    assert_response :forbidden
    assert_equal "forbidden", JSON.parse(response.body)["error"]
    assert_equal 30, @plaid_item.reload.sync_schedule.interval_minutes
  end

  test "members and guests cannot manage an admin-only provider's schedule" do
    guest_key = create_key(family_guest, "read_write")

    [ @member_key, guest_key ].each do |key|
      get schedule_url(@mercury_item, "mercury"), headers: api_headers(key)
      assert_response :forbidden

      patch schedule_url(@mercury_item, "mercury"), params: { sync_schedule: { interval_minutes: 30 } }.to_json,
        headers: api_headers(key)
      assert_response :forbidden
    end
    assert_nil @mercury_item.reload.sync_schedule
  end

  test "a connection being deleted, another family's connection and a bad id are 404" do
    other_family = Family.create!(name: "Other", currency: "USD", locale: "en")
    other_item = other_family.mercury_items.create!(name: "Theirs", token: "other-token")
    deleting = @admin.family.mercury_items.create!(name: "Going", token: "going-token", scheduled_for_deletion: true)

    [ other_item.id, deleting.id, SecureRandom.uuid, "nope" ].each do |id|
      get api_v1_provider_connection_sync_schedule_url(id), headers: api_headers(@admin_key)
      assert_response :not_found

      patch api_v1_provider_connection_sync_schedule_url(id), params: { sync_schedule: { interval_minutes: 30 } }.to_json,
        headers: api_headers(@admin_key)
      assert_response :not_found
    end
  end

  test "a FinanceKit connection takes no schedule" do
    financekit_setup(user: @admin)

    patch schedule_url(@item, "financekit"), params: { sync_schedule: { interval_minutes: 30 } }.to_json,
      headers: api_headers(@admin_key)

    assert_response :unprocessable_entity
    assert_equal "sync_schedule_not_supported", JSON.parse(response.body)["error"]
    assert_nil @item.reload.sync_schedule
  end

  test "requires authentication" do
    get schedule_url(@plaid_item, "plaid")
    assert_response :unauthorized

    patch schedule_url(@plaid_item, "plaid"), params: { sync_schedule: { interval_minutes: 30 } }.to_json,
      headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized
  end

  private
    def schedule_url(item, provider = nil)
      api_v1_provider_connection_sync_schedule_url(item, provider: provider)
    end

    def create_key(user, scope)
      ApiKey.create!(
        user: user,
        name: "Schedule #{scope} #{SecureRandom.hex(4)}",
        scopes: [ scope ],
        source: "web",
        display_key: "test_#{scope}_#{SecureRandom.hex(8)}"
      )
    end

    def api_headers(api_key)
      { "X-Api-Key" => api_key.plain_key, "Content-Type" => "application/json" }
    end
end
