# frozen_string_literal: true

require "test_helper"

class Api::V1::GoalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => true))
    @goal = goals(:vacation_italy)
    @depository = accounts(:depository)
    @connected = accounts(:connected)

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

  test "lists family goals with progress fields" do
    get api_v1_goals_url, headers: api_headers(@api_key)

    assert_response :success
    goals = response.parsed_body.fetch("goals")
    assert_equal goals(:vacation_italy, :emergency_fund, :car_paydown).map(&:id).sort, goals.pluck("id").sort

    row = goals.find { |g| g["id"] == @goal.id }
    expected = Goal.prepared_for(@user.family, scope: @user.family.goals.where(id: @goal.id)).first
    assert_equal "Vacation in Italy", row["name"]
    assert_equal 500_000, row["target_amount_cents"]
    assert_equal expected.progress_percent, row["progress_percent"]
    assert_equal expected.status.to_s, row["status"]
    assert_equal money_cents(expected.current_balance_money), row["current_amount_cents"]
    assert_equal money_cents(expected.remaining_amount_money), row["remaining_amount_cents"]
    assert_equal 1, row["pending_pledges_count"]
    assert_equal goal_pledges(:open_transfer).id, row["open_pledges"].first["id"]
    assert_equal [ @connected.id, @depository.id ].sort, row["linked_accounts"].pluck("id").sort
    %w[monthly_target_amount_cents pace_cents catch_up_amount_cents days_left projected_completion_date
       display_status behind_pace status_callout linked_account_count].each do |key|
      assert row.key?(key), "missing #{key}"
    end
  end

  test "lists active goals before paused ones" do
    get api_v1_goals_url, headers: api_headers(@api_key)

    ids = response.parsed_body.fetch("goals").pluck("id")
    assert_equal goals(:car_paydown).id, ids.last
  end

  test "filters goals by state" do
    get api_v1_goals_url, params: { state: "paused" }, headers: api_headers(@api_key)

    assert_response :success
    assert_equal [ goals(:car_paydown).id ], response.parsed_body.fetch("goals").pluck("id")
  end

  test "rejects an unknown state filter" do
    get api_v1_goals_url, params: { state: "bogus" }, headers: api_headers(@api_key)

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["error"]
  end

  test "shows a goal" do
    get api_v1_goal_url(@goal), headers: api_headers(@read_only_api_key)

    assert_response :success
    assert_equal @goal.id, response.parsed_body["id"]
    assert_equal "USD", response.parsed_body["currency"]
  end

  test "returns 404 for another family's goal or a malformed id" do
    other_family = Family.create!(name: "Other", currency: "USD", locale: "en")
    other_account = Account.create!(family: other_family, accountable: Depository.new, name: "Other", currency: "USD", balance: 10)
    other_goal = other_family.goals.new(name: "Theirs", target_amount: 100, currency: "USD")
    other_goal.goal_accounts.build(account: other_account)
    other_goal.save!

    get api_v1_goal_url(other_goal), headers: api_headers(@api_key)
    assert_response :not_found

    get api_v1_goal_url("not-a-uuid"), headers: api_headers(@api_key)
    assert_response :not_found
  end

  test "requires authentication" do
    get api_v1_goals_url

    assert_response :unauthorized
  end

  test "refuses users without preview features" do
    @user.update!(preferences: @user.preferences.merge("preview_features_enabled" => false))

    get api_v1_goals_url, headers: api_headers(@api_key)

    assert_response :forbidden
    assert_equal "feature_disabled", response.parsed_body["error"]
  end

  test "creates a goal linked to accessible accounts" do
    assert_difference -> { @user.family.goals.count }, 1 do
      post api_v1_goals_url, params: {
        goal: {
          name: "New bike", target_amount: "1200", target_date: 6.months.from_now.to_date.to_s,
          color: "#4da568", notes: "Gravel", account_ids: [ @connected.id ],
          allocations: { @connected.id => "300" }
        }
      }, headers: api_headers(@api_key), as: :json
    end

    assert_response :created
    body = response.parsed_body
    goal = Goal.find(body["id"])
    assert_equal "New bike", goal.name
    assert_equal @user.family.primary_currency_code, goal.currency
    assert_equal [ @connected.id ], goal.goal_accounts.pluck(:account_id)
    assert_equal 300, goal.goal_accounts.first.allocated_amount
    assert_equal 30_000, body["linked_accounts"].first["allocated_amount_cents"]
    assert_equal false, body["linked_accounts"].first["whole_account"]
  end

  test "create assigns a color when none is given" do
    post api_v1_goals_url, params: {
      goal: { name: "No color", target_amount: "100", account_ids: [ @connected.id ], allocations: { @connected.id => "10" } }
    }, headers: api_headers(@api_key), as: :json

    assert_response :created
    assert_includes Goal::COLORS, response.parsed_body["color"]
  end

  test "create returns validation errors" do
    assert_no_difference -> { Goal.count } do
      post api_v1_goals_url, params: { goal: { name: "", target_amount: "0", account_ids: [] } },
           headers: api_headers(@api_key), as: :json
    end

    assert_response :unprocessable_entity
    body = response.parsed_body
    assert_equal "validation_failed", body["error"]
    assert body["errors"].any?
  end

  test "create ignores accounts the user cannot access" do
    private_account = member_private_account

    assert_no_difference -> { Goal.count } do
      post api_v1_goals_url, params: {
        goal: { name: "Sneaky", target_amount: "100", account_ids: [ private_account.id ] }
      }, headers: api_headers(@api_key), as: :json
    end

    assert_response :unprocessable_entity
  end

  test "a member can link an account shared with them" do
    member = users(:family_member)
    member.update!(preferences: (member.preferences || {}).merge("preview_features_enabled" => true))
    member_key = ApiKey.create!(
      user: member, name: "Member RW", scopes: [ "read_write" ], source: "web",
      display_key: "test_member_#{SecureRandom.hex(8)}"
    )

    post api_v1_goals_url, params: {
      goal: { name: "Shared", target_amount: "100", account_ids: [ @depository.id, @connected.id ],
              allocations: { @depository.id => "20" } }
    }, headers: api_headers(member_key), as: :json

    assert_response :created
    assert_equal [ @depository.id ], Goal.find(response.parsed_body["id"]).goal_accounts.pluck(:account_id)
  end

  test "create ignores non-fundable account types" do
    assert_no_difference -> { Goal.count } do
      post api_v1_goals_url, params: {
        goal: { name: "Card", target_amount: "100", account_ids: [ accounts(:credit_card).id ] }
      }, headers: api_headers(@api_key), as: :json
    end

    assert_response :unprocessable_entity
  end

  test "read-only key cannot write" do
    post api_v1_goals_url, params: { goal: { name: "x", target_amount: "1" } }, headers: api_headers(@read_only_api_key), as: :json
    assert_response :forbidden

    patch api_v1_goal_url(@goal), params: { goal: { name: "x" } }, headers: api_headers(@read_only_api_key), as: :json
    assert_response :forbidden

    delete api_v1_goal_url(@goal), headers: api_headers(@read_only_api_key)
    assert_response :forbidden
    assert Goal.exists?(@goal.id)
  end

  test "updates goal attributes without touching links" do
    patch api_v1_goal_url(@goal), params: { goal: { name: "Rome", target_amount: "6000", icon: nil } },
          headers: api_headers(@api_key), as: :json

    assert_response :success
    @goal.reload
    assert_equal "Rome", @goal.name
    assert_equal 6000, @goal.target_amount
    assert_equal [ @connected.id, @depository.id ].sort, @goal.goal_accounts.pluck(:account_id).sort
    assert_equal 600_000, response.parsed_body["target_amount_cents"]
  end

  test "update replaces linked accounts" do
    patch api_v1_goal_url(@goal), params: { goal: { account_ids: [ @connected.id ] } },
          headers: api_headers(@api_key), as: :json

    assert_response :success
    assert_equal [ @connected.id ], @goal.reload.goal_accounts.pluck(:account_id)
  end

  test "update with no accessible accounts returns 422 and keeps links" do
    patch api_v1_goal_url(@goal), params: { goal: { account_ids: [ "" ] } }, headers: api_headers(@api_key), as: :json

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["error"]
    assert_equal 2, @goal.reload.goal_accounts.count
  end

  test "update preserves a link to an account the user cannot access and hides it" do
    private_account = member_private_account
    @goal.goal_accounts.create!(account: private_account, allocated_amount: 50)

    patch api_v1_goal_url(@goal), params: { goal: { account_ids: [ @depository.id ] } },
          headers: api_headers(@api_key), as: :json

    assert_response :success
    linked = @goal.reload.goal_accounts.pluck(:account_id)
    assert_includes linked, private_account.id
    assert_not_includes linked, @connected.id
    assert_not_includes response.parsed_body["linked_accounts"].pluck("id"), private_account.id
    assert_equal 2, response.parsed_body["linked_account_count"]
    assert_no_match(/Member Private Checking/, response.body)
  end

  test "update returns validation errors" do
    patch api_v1_goal_url(@goal), params: { goal: { target_amount: "-5" } }, headers: api_headers(@api_key), as: :json

    assert_response :unprocessable_entity
    assert response.parsed_body["errors"].any?
  end

  test "update returns 404 for an unknown goal" do
    patch api_v1_goal_url(SecureRandom.uuid), params: { goal: { name: "x" } }, headers: api_headers(@api_key), as: :json

    assert_response :not_found
  end

  test "destroys a goal and its links but no accounts" do
    assert_difference -> { Goal.count } => -1, -> { GoalAccount.count } => -2, -> { Account.count } => 0 do
      delete api_v1_goal_url(@goal), headers: api_headers(@api_key)
    end

    assert_response :success
    assert_equal "Goal deleted successfully", response.parsed_body["message"]
  end

  test "summary returns the goals index KPI figures and the active totals" do
    get summary_api_v1_goals_url, headers: api_headers(@read_only_api_key)

    assert_response :success
    body = response.parsed_body
    active_goals = Goal.active_prepared_for(@user.family)
    kpi = Goal::KpiSummary.new(@user.family, active_goals).to_h
    totals = Goal.summary_for(active_goals, currency: "USD")

    assert_equal "USD", body["currency"]
    assert_equal 3, body["active_total"]
    assert_equal 1, body["paused_count"]
    %w[on_track_count tracked_total reached_count behind_count no_date_count].each do |key|
      assert_equal kpi[key.to_sym], body[key], key
    end
    assert_equal money_cents(kpi[:velocity_30d_signed_money]), body["velocity_30d_cents"]
    assert_equal money_cents(kpi[:velocity_prior_30d_signed_money]), body["velocity_prior_30d_cents"]
    assert_equal kpi[:velocity_direction].to_s, body["velocity_direction"]
    assert_equal money_cents(kpi[:needs_this_month_money]), body["needs_this_month_cents"]
    assert_equal money_cents(totals[:saved_money]), body["saved_cents"]
    assert_equal 2_300_000, body["target_cents"]
    assert_equal 1, body["pending_pledges_count"]
  end

  test "summary leaves out completed and archived goals" do
    goals(:emergency_fund).complete!
    goals(:car_paydown).archive!

    get summary_api_v1_goals_url, headers: api_headers(@api_key)

    assert_response :success
    assert_equal 1, response.parsed_body["active_total"]
    assert_equal 500_000, response.parsed_body["target_cents"]
  end

  test "summary requires authentication and preview features" do
    get summary_api_v1_goals_url
    assert_response :unauthorized

    @user.update!(preferences: @user.preferences.merge("preview_features_enabled" => false))
    get summary_api_v1_goals_url, headers: api_headers(@api_key)
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

    def money_cents(money)
      (money.amount * money.currency.minor_unit_conversion).round(0).to_i
    end
end
