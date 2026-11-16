# frozen_string_literal: true

require "test_helper"

class Api::V1::AccountSharingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:family_admin)
    @member = users(:family_member)
    @family = @owner.family
    @account = accounts(:depository)
    @guest = @family.users.create!(
      email: "guest-sharing@example.com", first_name: "Gus", last_name: "Guest", role: "guest",
      password: user_password_test, password_confirmation: user_password_test
    )

    @owner_write_key = api_key_for(@owner, %w[read_write])
    @owner_read_key = api_key_for(@owner, %w[read])
    @member_write_key = api_key_for(@member, %w[read_write])
  end

  test "owner sees every eligible member with the web's permission names" do
    get api_v1_account_sharing_url(@account), headers: api_headers(@owner_read_key)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["is_owner"]
    assert_nil body["include_in_finances"]
    assert_equal AccountShare::PERMISSIONS, body["permissions"]
    assert_equal({ "id" => @owner.id, "name" => @owner.display_name }, body["owner"])

    permissions = body["members"].to_h { |m| [ m["user_id"], m["permission"] ] }
    assert_equal({ @member.id => "full_control", @guest.id => "none" }, permissions)
    assert_not_includes permissions.keys, @owner.id
  end

  test "a member the account is shared with sees their own share and no member list" do
    get api_v1_account_sharing_url(@account), headers: api_headers(@member_write_key)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal false, body["is_owner"]
    assert_equal "full_control", body["permission"]
    assert_equal true, body["include_in_finances"]
    assert_equal [], body["members"]
  end

  test "owner shares, changes and unshares in one request" do
    patch api_v1_account_sharing_url(@account),
          params: { sharing: { members: [
            { user_id: @member.id, permission: "none" },
            { user_id: @guest.id, permission: "read_write" }
          ] } },
          headers: api_headers(@owner_write_key), as: :json

    assert_response :success
    assert_nil @account.account_shares.find_by(user: @member)
    guest_share = @account.account_shares.find_by!(user: @guest)
    assert_equal "read_write", guest_share.permission
    assert_equal true, guest_share.include_in_finances

    permissions = JSON.parse(response.body)["members"].to_h { |m| [ m["user_id"], m["permission"] ] }
    assert_equal({ @member.id => "none", @guest.id => "read_write" }, permissions)

    patch api_v1_account_sharing_url(@account),
          params: { sharing: { members: [ { user_id: @guest.id, permission: "read_only" } ] } },
          headers: api_headers(@owner_write_key), as: :json
    assert_response :success
    assert_equal "read_only", guest_share.reload.permission
  end

  test "owner update rejects unknown permissions and ineligible users without writing" do
    patch api_v1_account_sharing_url(@account),
          params: { sharing: { members: [ { user_id: @guest.id, permission: "read_write" }, { user_id: @member.id, permission: "admin" } ] } },
          headers: api_headers(@owner_write_key), as: :json
    assert_response :unprocessable_entity
    assert_nil @account.account_shares.find_by(user: @guest)

    [ @owner.id, users(:empty).id ].each do |user_id|
      patch api_v1_account_sharing_url(@account),
            params: { sharing: { members: [ { user_id: user_id, permission: "read_only" } ] } },
            headers: api_headers(@owner_write_key), as: :json
      assert_response :unprocessable_entity
      assert_equal "validation_failed", JSON.parse(response.body)["error"]
    end

    patch api_v1_account_sharing_url(@account),
          params: { sharing: { include_in_finances: false } },
          headers: api_headers(@owner_write_key), as: :json
    assert_response :unprocessable_entity
  end

  test "a shared member can only change their own include_in_finances" do
    patch api_v1_account_sharing_url(@account),
          params: { sharing: { include_in_finances: false } },
          headers: api_headers(@member_write_key), as: :json

    assert_response :success
    assert_equal false, @account.account_shares.find_by!(user: @member).include_in_finances
    assert_equal false, JSON.parse(response.body)["include_in_finances"]
  end

  test "non-owners get 403 for member changes, even with full control" do
    patch api_v1_account_sharing_url(@account),
          params: { sharing: { members: [ { user_id: @guest.id, permission: "read_only" } ] } },
          headers: api_headers(@member_write_key), as: :json

    assert_response :forbidden
    assert_equal "forbidden", JSON.parse(response.body)["error"]
    assert_nil @account.account_shares.find_by(user: @guest)
  end

  test "accounts the caller cannot access return 404" do
    other_account = Account.create!(
      family: families(:empty), owner: users(:empty), name: "Elsewhere", balance: 0, currency: "USD",
      accountable: Depository.new
    )

    get api_v1_account_sharing_url(other_account), headers: api_headers(@owner_read_key)
    assert_response :not_found

    unshared = accounts(:other_asset)
    get api_v1_account_sharing_url(unshared), headers: api_headers(@member_write_key)
    assert_response :not_found

    get api_v1_account_sharing_url("not-a-uuid"), headers: api_headers(@owner_read_key)
    assert_response :not_found
  end

  test "update requires the read_write scope and authentication" do
    patch api_v1_account_sharing_url(@account),
          params: { sharing: { members: [ { user_id: @guest.id, permission: "read_only" } ] } },
          headers: api_headers(@owner_read_key), as: :json
    assert_response :forbidden
    assert_equal "insufficient_scope", JSON.parse(response.body)["error"]

    get api_v1_account_sharing_url(@account)
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
