# frozen_string_literal: true

require "test_helper"

class Api::V1::BudgetSharesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:family_admin)
    @member = users(:family_member)
    @family = @owner.family
    @family.update!(personal_budgets: true)
    @guest = @family.users.create!(
      email: "guest-budget@example.com", first_name: "Gus", last_name: "Guest", role: "guest",
      password: user_password_test, password_confirmation: user_password_test
    )

    @write_key = api_key_for(@owner, %w[read_write])
    @read_key = api_key_for(@owner, %w[read])
  end

  test "shows every other active member with the caller's grant" do
    @owner.budget_shares_given.create!(viewer: @member, permission: "read_write")
    @family.users.create!(
      email: "inactive-budget@example.com", first_name: "In", last_name: "Active", role: "member", active: false,
      password: user_password_test, password_confirmation: user_password_test
    )

    get api_v1_budget_shares_url, headers: api_headers(@read_key)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["personal_budgets"]
    assert_equal BudgetShare::PERMISSIONS, body["permissions"]
    permissions = body["members"].to_h { |m| [ m["user_id"], m["permission"] ] }
    assert_equal({ @member.id => "read_write", @guest.id => "none" }, permissions)
  end

  test "grants, changes and revokes in one request" do
    @owner.budget_shares_given.create!(viewer: @member, permission: "read_write")

    patch api_v1_budget_shares_url,
          params: { budget_shares: { members: [
            { user_id: @member.id, permission: "none" },
            { user_id: @guest.id, permission: "read_only" }
          ] } },
          headers: api_headers(@write_key), as: :json

    assert_response :success
    assert_nil @owner.budget_shares_given.find_by(viewer: @member)
    assert_equal "read_only", @owner.budget_shares_given.find_by!(viewer: @guest).permission
    permissions = JSON.parse(response.body)["members"].to_h { |m| [ m["user_id"], m["permission"] ] }
    assert_equal({ @member.id => "none", @guest.id => "read_only" }, permissions)

    patch api_v1_budget_shares_url,
          params: { budget_shares: { members: [ { user_id: @guest.id, permission: "read_write" } ] } },
          headers: api_headers(@write_key), as: :json
    assert_response :success
    assert_equal "read_write", @owner.budget_shares_given.find_by!(viewer: @guest).permission
  end

  test "rejects unknown permissions, the caller and other families' users without writing" do
    patch api_v1_budget_shares_url,
          params: { budget_shares: { members: [ { user_id: @guest.id, permission: "read_only" }, { user_id: @member.id, permission: "full_control" } ] } },
          headers: api_headers(@write_key), as: :json
    assert_response :unprocessable_entity
    assert_nil @owner.budget_shares_given.find_by(viewer: @guest)

    [ @owner.id, users(:empty).id ].each do |user_id|
      patch api_v1_budget_shares_url,
            params: { budget_shares: { members: [ { user_id: user_id, permission: "read_only" } ] } },
            headers: api_headers(@write_key), as: :json
      assert_response :unprocessable_entity
      assert_equal "validation_failed", JSON.parse(response.body)["error"]
    end

    patch api_v1_budget_shares_url,
          params: { budget_shares: { members: "everyone" } },
          headers: api_headers(@write_key), as: :json
    assert_response :unprocessable_entity
  end

  test "a guest manages their own budget's sharing, as on the web" do
    guest_key = api_key_for(@guest, %w[read_write])

    patch api_v1_budget_shares_url,
          params: { budget_shares: { members: [ { user_id: @owner.id, permission: "read_only" } ] } },
          headers: api_headers(guest_key), as: :json

    assert_response :success
    assert_equal "read_only", @guest.budget_shares_given.find_by!(viewer: @owner).permission
  end

  test "update requires the read_write scope and authentication" do
    patch api_v1_budget_shares_url,
          params: { budget_shares: { members: [ { user_id: @guest.id, permission: "read_only" } ] } },
          headers: api_headers(@read_key), as: :json
    assert_response :forbidden
    assert_equal "insufficient_scope", JSON.parse(response.body)["error"]

    get api_v1_budget_shares_url
    assert_response :unauthorized
  end

  private

    def api_key_for(user, scopes)
      key = ApiKey.create!(
        user: user,
        name: "Test #{scopes.join} #{SecureRandom.hex(3)}",
        scopes: scopes,
        source: "web",
        display_key: "test_#{SecureRandom.hex(12)}"
      )
      Redis.new.del("api_rate_limit:#{key.id}")
      key
    end
end
