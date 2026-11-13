# frozen_string_literal: true

require "test_helper"

class Api::V1::AccountPermissionsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @member = users(:family_member)
    @user.api_keys.active.destroy_all
    @member.api_keys.active.destroy_all
    @owner_key = api_key_for(@user)
    @member_key = api_key_for(@member)
  end

  test "owner can edit and delete a manual account" do
    get "/api/v1/accounts/#{accounts(:depository).id}", headers: api_headers(@owner_key)

    assert_response :success
    body = response.parsed_body
    assert_equal false, body["linked"]
    assert_equal({ "edit" => true, "delete" => true }, body["permissions"])
    assert_equal [], body["locked_fields"]
  end

  test "linked account is editable but not deletable and locks provider fields" do
    get "/api/v1/accounts/#{accounts(:connected).id}", headers: api_headers(@owner_key)

    body = response.parsed_body
    assert_equal true, body["linked"]
    assert_equal({ "edit" => true, "delete" => false }, body["permissions"])
    assert_equal %w[balance currency], body["locked_fields"]
  end

  test "linked vehicle also locks its purchase fields" do
    account = accounts(:vehicle)
    account.update!(plaid_account: plaid_accounts(:one))

    get "/api/v1/accounts/#{account.id}", headers: api_headers(@owner_key)

    assert_equal %w[
      balance currency accountable_attributes.initial_balance
      accountable_attributes.initial_balance_shown accountable_attributes.purchase_date
    ], response.parsed_body["locked_fields"]
  end

  test "share permission decides what a member can do" do
    get "/api/v1/accounts", headers: api_headers(@member_key)

    assert_response :success
    by_id = response.parsed_body["accounts"].index_by { |a| a["id"] }
    assert_equal({ "edit" => true, "delete" => true }, by_id[accounts(:depository).id]["permissions"])
    assert_equal({ "edit" => false, "delete" => false }, by_id[accounts(:credit_card).id]["permissions"])
  end

  test "reported permissions match what the write endpoints allow" do
    get "/api/v1/accounts/#{accounts(:credit_card).id}", headers: api_headers(@member_key)
    assert_equal false, response.parsed_body.dig("permissions", "edit")
    patch "/api/v1/accounts/#{accounts(:credit_card).id}", params: { account: { name: "Nope" } }, headers: api_headers(@member_key)
    assert_response :forbidden

    get "/api/v1/accounts/#{accounts(:connected).id}", headers: api_headers(@owner_key)
    locked = response.parsed_body["locked_fields"]
    patch "/api/v1/accounts/#{accounts(:connected).id}", params: { account: { balance: 1, currency: "EUR" } },
      headers: api_headers(@owner_key)
    assert_response :unprocessable_entity
    assert_equal "Linked accounts cannot change: #{locked.join(', ')}", response.parsed_body["message"]
  end

  test "index loads shares and providers without a query per account" do
    accounts(:loan).share_with!(@member, permission: "read_write")
    accounts(:connected).share_with!(@member, permission: "full_control")
    get "/api/v1/accounts", headers: api_headers(@member_key) # warm up

    queries = []
    callback = ->(*, payload) { queries << payload[:sql] unless payload[:name].in?([ "SCHEMA", "CACHE" ]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get "/api/v1/accounts", headers: api_headers(@member_key)
    end

    assert_response :success
    assert_equal 4, response.parsed_body["accounts"].size
    %w[account_shares plaid_accounts].each do |table|
      count = queries.count { |sql| sql.start_with?("SELECT \"#{table}\".* FROM \"#{table}\"") }
      assert_operator count, :<=, 1, "#{table} queried #{count} times"
    end
  end

  private

    def api_key_for(user)
      ApiKey.create!(user: user, name: "rw key", scopes: [ "read_write" ], source: "web",
        display_key: "rw_#{SecureRandom.hex(8)}")
    end

    def api_headers(api_key)
      { "X-Api-Key" => api_key.plain_key }
    end
end
