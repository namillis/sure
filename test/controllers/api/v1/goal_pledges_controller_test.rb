# frozen_string_literal: true

require "test_helper"

class Api::V1::GoalPledgesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => true))
    @goal = goals(:vacation_italy)
    @depository = accounts(:depository)
    @connected = accounts(:connected)
    @open_pledge = goal_pledges(:open_transfer)

    @user.api_keys.active.destroy_all
    @api_key = ApiKey.create!(
      user: @user, name: "Pledges RW", scopes: [ "read_write" ], source: "web",
      display_key: "test_rw_#{SecureRandom.hex(8)}"
    )
    @read_only_api_key = ApiKey.create!(
      user: @user, name: "Pledges RO", scopes: [ "read" ], source: "mobile",
      display_key: "test_read_#{SecureRandom.hex(8)}"
    )
  end

  test "creates a pledge and returns it with the refreshed goal" do
    assert_difference -> { @goal.goal_pledges.count }, 1 do
      post api_v1_goal_pledges_url(@goal), params: { pledge: { amount: "150", account_id: @connected.id } },
           headers: api_headers(@api_key), as: :json
    end

    assert_response :created
    body = response.parsed_body
    pledge = GoalPledge.find(body["pledge"]["id"])
    assert_equal @connected.id, pledge.account_id
    assert_equal @connected.default_pledge_kind, pledge.kind
    assert_equal @goal.currency, pledge.currency
    assert pledge.status_open?
    assert_equal 15_000, body["pledge"]["amount_cents"]
    assert_equal @goal.id, body["goal"]["id"]
    assert_equal 2, body["goal"]["pending_pledges_count"]
  end

  test "create refuses an account not linked to the goal" do
    assert_no_difference -> { GoalPledge.count } do
      post api_v1_goal_pledges_url(@goal), params: { pledge: { amount: "150", account_id: accounts(:investment).id } },
           headers: api_headers(@api_key), as: :json
    end

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["error"]
  end

  test "create refuses a linked account the user cannot access" do
    private_account = Account.create!(
      family: @user.family, owner: users(:family_member), accountable: Depository.new,
      name: "Member Private Checking", currency: "USD", balance: 100
    )
    @goal.goal_accounts.create!(account: private_account, allocated_amount: 50)

    assert_no_difference -> { GoalPledge.count } do
      post api_v1_goal_pledges_url(@goal), params: { pledge: { amount: "10", account_id: private_account.id } },
           headers: api_headers(@api_key), as: :json
    end

    assert_response :unprocessable_entity
  end

  test "create returns validation errors for a bad amount or a duplicate" do
    post api_v1_goal_pledges_url(@goal), params: { pledge: { amount: "0", account_id: @connected.id } },
         headers: api_headers(@api_key), as: :json
    assert_response :unprocessable_entity
    assert response.parsed_body["errors"].any?

    post api_v1_goal_pledges_url(@goal), params: { pledge: { amount: @open_pledge.amount.to_s, account_id: @depository.id } },
         headers: api_headers(@api_key), as: :json
    assert_response :unprocessable_entity
  end

  test "cancels an open pledge" do
    delete api_v1_goal_pledge_url(@goal, @open_pledge), headers: api_headers(@api_key)

    assert_response :success
    assert @open_pledge.reload.status_cancelled?
    assert_equal "cancelled", response.parsed_body["pledge"]["status"]
    assert_equal 0, response.parsed_body["goal"]["pending_pledges_count"]
  end

  test "cancelling a pledge that is not open returns 422" do
    delete api_v1_goal_pledge_url(@goal, goal_pledges(:matched_transfer)), headers: api_headers(@api_key)

    assert_response :unprocessable_entity
    assert_equal "pledge_not_open", response.parsed_body["error"]
    assert goal_pledges(:matched_transfer).reload.status_matched?
  end

  test "renews an open pledge" do
    expires_at = @open_pledge.expires_at

    patch renew_api_v1_goal_pledge_url(@goal, @open_pledge), headers: api_headers(@api_key)

    assert_response :success
    assert_in_delta (expires_at + GoalPledge::EXTEND_DAYS.days).to_f, @open_pledge.reload.expires_at.to_f, 1
  end

  test "returns 404 for a pledge on another goal or an unknown goal" do
    delete api_v1_goal_pledge_url(goals(:emergency_fund), @open_pledge), headers: api_headers(@api_key)
    assert_response :not_found

    post api_v1_goal_pledges_url(SecureRandom.uuid), params: { pledge: { amount: "1" } }, headers: api_headers(@api_key), as: :json
    assert_response :not_found
  end

  test "read-only key cannot write pledges" do
    post api_v1_goal_pledges_url(@goal), params: { pledge: { amount: "1", account_id: @connected.id } },
         headers: api_headers(@read_only_api_key), as: :json
    assert_response :forbidden

    delete api_v1_goal_pledge_url(@goal, @open_pledge), headers: api_headers(@read_only_api_key)
    assert_response :forbidden
    assert @open_pledge.reload.status_open?
  end

  test "requires authentication and preview features" do
    delete api_v1_goal_pledge_url(@goal, @open_pledge)
    assert_response :unauthorized

    @user.update!(preferences: @user.preferences.merge("preview_features_enabled" => false))
    delete api_v1_goal_pledge_url(@goal, @open_pledge), headers: api_headers(@api_key)
    assert_response :forbidden
    assert_equal "feature_disabled", response.parsed_body["error"]
  end
end
