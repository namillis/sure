# frozen_string_literal: true

require "test_helper"

class Api::V1::GoalActionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => true))
    @goal = goals(:emergency_fund)

    @user.api_keys.active.destroy_all
    @api_key = ApiKey.create!(
      user: @user, name: "Goals RW", scopes: [ "read_write" ], source: "web",
      display_key: "test_rw_#{SecureRandom.hex(8)}"
    )
    @read_only_api_key = ApiKey.create!(
      user: @user, name: "Goals RO", scopes: [ "read" ], source: "mobile",
      display_key: "test_read_#{SecureRandom.hex(8)}"
    )
  end

  test "pause, resume, complete, reopen, archive and unarchive move the goal through its states" do
    [
      [ :pause, "paused" ], [ :resume, "active" ], [ :complete, "completed" ], [ :reopen, "active" ],
      [ :archive, "archived" ], [ :unarchive, "active" ]
    ].each do |event, state|
      patch "/api/v1/goals/#{@goal.id}/#{event}", headers: api_headers(@api_key)

      assert_response :success, "#{event} failed: #{response.body}"
      assert_equal state, response.parsed_body["state"]
      assert_equal state, @goal.reload.state
    end
  end

  test "a transition the state machine refuses returns invalid_transition with a showable message" do
    patch "/api/v1/goals/#{@goal.id}/resume", headers: api_headers(@api_key)

    assert_response :unprocessable_entity
    assert_equal "invalid_transition", response.parsed_body["error"]
    assert_equal I18n.t("goals.resume.invalid_transition"), response.parsed_body["message"]
    assert_equal "active", @goal.reload.state
  end

  test "a maintained goal cannot be completed" do
    @goal.update!(kind: "maintained")

    patch "/api/v1/goals/#{@goal.id}/complete", headers: api_headers(@api_key)

    assert_response :unprocessable_entity
    assert_equal "invalid_transition", response.parsed_body["error"]
  end

  test "a transition whose save fails validation reports the validation error" do
    Goal.any_instance.stubs(:pause!).returns(false)

    patch "/api/v1/goals/#{@goal.id}/pause", headers: api_headers(@api_key)

    assert_response :unprocessable_entity
    assert_equal "invalid_transition", response.parsed_body["error"]
    assert_equal "active", @goal.reload.state
  end

  test "available_actions lists the transitions the goal's state permits" do
    get api_v1_goal_url(@goal), headers: api_headers(@api_key)
    assert_equal %w[archive complete consume pause], response.parsed_body["available_actions"].sort

    get api_v1_goal_url(goals(:car_paydown)), headers: api_headers(@api_key)
    assert_equal %w[archive complete resume], response.parsed_body["available_actions"].sort

    @goal.update!(kind: "maintained")
    get api_v1_goal_url(@goal), headers: api_headers(@api_key)
    assert_equal %w[archive pause], response.parsed_body["available_actions"].sort
  end

  test "available_actions omits consume when only an inaccessible account backs the goal" do
    goal = @user.family.goals.new(name: "Private pot", target_amount: 500, currency: "USD")
    goal.goal_accounts.build(account: member_private_account, allocated_amount: 50)
    goal.save!

    get api_v1_goal_url(goal), headers: api_headers(@api_key)

    assert_not_includes response.parsed_body["available_actions"], "consume"
  end

  test "consume records a spend and returns 201 with the goal" do
    post "/api/v1/goals/#{@goal.id}/consume", params: { consumption: { amount: "200" } }, headers: api_headers(@api_key)

    assert_response :created
    assert_equal @goal.id, response.parsed_body["id"]
    assert_equal 20_000, response.parsed_body["consumed_amount_cents"]
    assert_equal 200, @goal.reload.consumed_amount
    assert_equal 800, @goal.goal_accounts.first.allocated_amount
  end

  test "consume attributes a detected outflow by transaction id" do
    goal, entry = goal_with_outflow

    post "/api/v1/goals/#{goal.id}/consume", params: { consumption: { transaction_id: entry.entryable_id } },
                                             headers: api_headers(@api_key)

    assert_response :created
    assert_equal entry.amount.to_d, goal.reload.consumed_amount
    assert_equal goal.id, entry.entryable.reload.extra.dig("goal", "consumed_goal_id")
  end

  test "a refused spend returns the model's reason and message" do
    @goal.update!(kind: "maintained")

    post "/api/v1/goals/#{@goal.id}/consume", params: { consumption: { amount: "100" } }, headers: api_headers(@api_key)

    assert_response :unprocessable_entity
    assert_equal "consumption_refused", response.parsed_body["error"]
    assert_equal "maintained", response.parsed_body["reason"]
    assert_equal I18n.t("goals.consume.errors.maintained"), response.parsed_body["message"]
    assert_equal 0, @goal.reload.consumed_amount
  end

  test "consume refuses a linked account the caller cannot see" do
    private_account = member_private_account
    link = @goal.goal_accounts.create!(account: private_account, allocated_amount: 50)

    post "/api/v1/goals/#{@goal.id}/consume", params: { consumption: { amount: "10", account_id: private_account.id } },
                                              headers: api_headers(@api_key)

    assert_response :unprocessable_entity
    assert_equal "account_not_linked", response.parsed_body["reason"]
    assert_equal 50, link.reload.allocated_amount
    assert_equal 0, @goal.reload.consumed_amount
  end

  test "consume without a consumption body is a bad request" do
    post "/api/v1/goals/#{@goal.id}/consume", headers: api_headers(@api_key)

    assert_response :bad_request
  end

  test "read-only key cannot change a goal" do
    patch "/api/v1/goals/#{@goal.id}/pause", headers: api_headers(@read_only_api_key)
    assert_response :forbidden

    post "/api/v1/goals/#{@goal.id}/consume", params: { consumption: { amount: "10" } }, headers: api_headers(@read_only_api_key)
    assert_response :forbidden

    assert_equal "active", @goal.reload.state
    assert_equal 0, @goal.consumed_amount
  end

  test "returns 404 for another family's goal or a malformed id" do
    other_family = Family.create!(name: "Other", currency: "USD", locale: "en")
    other_account = Account.create!(family: other_family, accountable: Depository.new, name: "Other", currency: "USD", balance: 10)
    other_goal = other_family.goals.new(name: "Theirs", target_amount: 100, currency: "USD")
    other_goal.goal_accounts.build(account: other_account)
    other_goal.save!

    patch "/api/v1/goals/#{other_goal.id}/pause", headers: api_headers(@api_key)
    assert_response :not_found
    assert_equal "active", other_goal.reload.state

    post "/api/v1/goals/not-a-uuid/consume", params: { consumption: { amount: "1" } }, headers: api_headers(@api_key)
    assert_response :not_found
  end

  test "requires authentication" do
    patch "/api/v1/goals/#{@goal.id}/pause"

    assert_response :unauthorized
  end

  test "refuses users without preview features" do
    @user.update!(preferences: @user.preferences.merge("preview_features_enabled" => false))

    patch "/api/v1/goals/#{@goal.id}/pause", headers: api_headers(@api_key)

    assert_response :forbidden
    assert_equal "feature_disabled", response.parsed_body["error"]
  end

  private
    def member_private_account
      Account.create!(
        family: @user.family, owner: users(:family_member), accountable: Depository.new,
        name: "Member Private Checking", currency: "USD", balance: 100
      )
    end

    def goal_with_outflow
      account = Account.create!(
        family: @user.family, accountable: Depository.new,
        name: "Trip Pot #{SecureRandom.hex(4)}", currency: "USD", balance: 5_000
      )
      goal = @user.family.goals.create!(name: "Trip", target_amount: 5_000, currency: "USD") do |g|
        g.goal_accounts.build(account: account, allocated_amount: 5_000)
      end
      entry = account.entries.create!(
        name: "Flights", date: Date.current, amount: 1_200, currency: "USD", entryable: Transaction.new
      )
      [ goal, entry ]
    end
end
