# frozen_string_literal: true

require "test_helper"

class Api::V1::BudgetWritesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @user.api_keys.active.destroy_all

    @write_key = ApiKey.create!(
      user: @user,
      name: "Test Write Key",
      scopes: [ "read_write" ],
      source: "web",
      display_key: "test_rw_#{SecureRandom.hex(8)}"
    )

    @budget = @family.budgets.create!(
      start_date: 3.months.ago.beginning_of_month.to_date,
      end_date: 3.months.ago.end_of_month.to_date,
      budgeted_spending: 3000,
      expected_income: 5000,
      currency: "USD"
    )
  end

  test "updates budgeted spending and expected income" do
    patch api_v1_budget_url(@budget.id),
          params: { budget: { budgeted_spending: "3500.50", expected_income: 6000 } },
          headers: api_headers(@write_key),
          as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @budget.id, body["id"]
    assert_equal 350050, body["budgeted_spending_cents"]
    assert_equal 600000, body["expected_income_cents"]
    assert body.key?("available_to_allocate_cents")
    assert_equal 3500.50, @budget.reload.budgeted_spending.to_f
    assert_equal 6000, @budget.expected_income.to_i
  end

  test "accepts unwrapped attributes and leaves omitted fields alone" do
    patch api_v1_budget_url(@budget.id),
          params: { expected_income: 4200 },
          headers: api_headers(@write_key),
          as: :json

    assert_response :success
    assert_equal 4200, @budget.reload.expected_income.to_i
    assert_equal 3000, @budget.budgeted_spending.to_i
  end

  test "setting up a month recomputes the rollover chain" do
    calculator = mock
    calculator.expects(:recompute!).once
    Budget::RolloverCalculator.expects(:new).with(family: @family, user: nil).returns(calculator)

    patch api_v1_budget_url(@budget.id),
          params: { budget: { budgeted_spending: 100 } },
          headers: api_headers(@write_key),
          as: :json

    assert_response :success
  end

  test "rejects negative and non-numeric amounts" do
    [ -1, "abc", "", nil ].each do |bad_value|
      patch api_v1_budget_url(@budget.id),
            params: { budget: { budgeted_spending: bad_value } },
            headers: api_headers(@write_key),
            as: :json

      assert_response :unprocessable_entity
      body = JSON.parse(response.body)
      assert_equal "validation_failed", body["error"]
      assert_includes body["errors"], "budgeted_spending must be a number greater than or equal to 0"
    end

    assert_equal 3000, @budget.reload.budgeted_spending.to_i
  end

  test "rejects a request with no updatable fields" do
    patch api_v1_budget_url(@budget.id),
          params: { budget: { name: "ignored" } },
          headers: api_headers(@write_key),
          as: :json

    assert_response :unprocessable_entity
    assert_equal "validation_failed", JSON.parse(response.body)["error"]
  end

  test "returns not found for another family's budget and invalid ids" do
    other_budget = families(:empty).budgets.create!(
      start_date: 4.months.ago.beginning_of_month.to_date,
      end_date: 4.months.ago.end_of_month.to_date,
      budgeted_spending: 1000,
      currency: "USD"
    )

    patch api_v1_budget_url(other_budget.id), params: { budget: { budgeted_spending: 1 } },
          headers: api_headers(@write_key), as: :json
    assert_response :not_found
    assert_equal 1000, other_budget.reload.budgeted_spending.to_i

    patch api_v1_budget_url("not-a-uuid"), params: { budget: { budgeted_spending: 1 } },
          headers: api_headers(@write_key), as: :json
    assert_response :not_found
  end

  test "another member's unshared personal budget is not found" do
    member_budget = personal_budget_for(users(:family_member))

    patch api_v1_budget_url(member_budget.id), params: { budget: { budgeted_spending: 1 } },
          headers: api_headers(@write_key), as: :json

    assert_response :not_found
  end

  test "a read-only budget share cannot be edited" do
    member_budget = personal_budget_for(users(:family_member))
    BudgetShare.create!(owner: users(:family_member), viewer: @user, permission: "read_only")

    patch api_v1_budget_url(member_budget.id), params: { budget: { budgeted_spending: 1 } },
          headers: api_headers(@write_key), as: :json

    assert_response :forbidden
    assert_equal "forbidden", JSON.parse(response.body)["error"]
    assert_equal 800, member_budget.reload.budgeted_spending.to_i
  end

  test "a read-write budget share can be edited" do
    member_budget = personal_budget_for(users(:family_member))
    BudgetShare.create!(owner: users(:family_member), viewer: @user, permission: "read_write")

    patch api_v1_budget_url(member_budget.id), params: { budget: { budgeted_spending: 900 } },
          headers: api_headers(@write_key), as: :json

    assert_response :success
    assert_equal 900, member_budget.reload.budgeted_spending.to_i
  end

  test "requires authentication" do
    patch api_v1_budget_url(@budget.id), params: { budget: { budgeted_spending: 1 } }, as: :json

    assert_response :unauthorized
  end

  test "a read-only key cannot update" do
    read_key = ApiKey.create!(
      user: @user,
      name: "Test Read Key",
      scopes: [ "read" ],
      source: "mobile",
      display_key: "test_read_#{SecureRandom.hex(8)}"
    )

    patch api_v1_budget_url(@budget.id), params: { budget: { budgeted_spending: 1 } },
          headers: api_headers(read_key), as: :json

    assert_response :forbidden
    assert_equal "insufficient_scope", JSON.parse(response.body)["error"]
    assert_equal 3000, @budget.reload.budgeted_spending.to_i
  end

  test "creates a month with no budget row and returns the existing one after that" do
    month_start = 2.months.from_now.beginning_of_month.to_date

    assert_difference -> { @family.budgets.count }, 1 do
      post api_v1_budgets_url, params: { budget: { month: month_start.strftime("%Y-%m") } },
           headers: api_headers(@write_key), as: :json
    end

    assert_response :created
    body = JSON.parse(response.body)
    budget = @family.budgets.find(body["id"])
    assert_equal month_start, budget.start_date
    assert_nil budget.user_id
    assert_equal false, body["initialized"]
    assert_equal @family.categories.count, budget.budget_categories.count

    assert_no_difference -> { @family.budgets.count } do
      post api_v1_budgets_url, params: { budget: { month: month_start.strftime("%Y-%m") } },
           headers: api_headers(@write_key), as: :json
    end

    assert_response :success
    assert_equal budget.id, JSON.parse(response.body)["id"]
  end

  test "creating a month follows the family's custom month start" do
    @family.update!(month_start_day: 15)
    month = 2.months.from_now.to_date

    post api_v1_budgets_url, params: { budget: { month: month.strftime("%Y-%m") } },
         headers: api_headers(@write_key), as: :json

    assert_response :created
    assert_equal Date.new(month.year, month.month, 15), Date.parse(JSON.parse(response.body)["start_date"])
  end

  test "creating a month creates the caller's personal budget when personal budgets are on" do
    @family.update!(personal_budgets: true)
    month = 2.months.from_now.strftime("%Y-%m")

    post api_v1_budgets_url, params: { budget: { month: month } }, headers: api_headers(@write_key), as: :json
    assert_response :created
    assert_equal @user.id, @family.budgets.find(JSON.parse(response.body)["id"]).user_id

    post api_v1_budgets_url, params: { budget: { month: month }, owner: "household" }, headers: api_headers(@write_key), as: :json
    assert_response :created
    assert_nil @family.budgets.find(JSON.parse(response.body)["id"]).user_id
  end

  test "creating a month never creates another member's budget" do
    owner = users(:family_member)
    @family.update!(personal_budgets: true)
    BudgetShare.create!(owner: owner, viewer: @user, permission: "read_write")
    month = 2.months.from_now.strftime("%Y-%m")

    assert_no_difference -> { Budget.count } do
      post api_v1_budgets_url, params: { budget: { month: month }, owner: owner.id }, headers: api_headers(@write_key), as: :json
    end
    assert_response :not_found

    existing = personal_budget_for(owner)
    post api_v1_budgets_url, params: { budget: { month: existing.start_date.strftime("%Y-%m") }, owner: owner.id },
         headers: api_headers(@write_key), as: :json
    assert_response :success
    assert_equal existing.id, JSON.parse(response.body)["id"]

    post api_v1_budgets_url, params: { budget: { month: month }, owner: users(:empty).id }, headers: api_headers(@write_key), as: :json
    assert_response :not_found
  end

  test "creating a month rejects a malformed or out-of-range month" do
    [ "2026-13", "dec-2026", "", nil ].each do |bad_month|
      post api_v1_budgets_url, params: { budget: { month: bad_month } }, headers: api_headers(@write_key), as: :json

      assert_response :unprocessable_entity
      assert_includes JSON.parse(response.body)["errors"], "month must look like 2026-12"
    end

    post api_v1_budgets_url, params: { budget: { month: 5.years.from_now.strftime("%Y-%m") } },
         headers: api_headers(@write_key), as: :json
    assert_response :unprocessable_entity
    assert_equal "validation_failed", JSON.parse(response.body)["error"]
  end

  test "copies the previous initialized month into an empty one" do
    category = @family.categories.create!(name: "Copy API test", color: "#123456")
    @budget.sync_budget_categories
    @budget.budget_categories.find_by!(category: category).update!(budgeted_spending: 250, rollover_enabled: true)
    target_start = 2.months.ago.beginning_of_month.to_date

    post copy_previous_api_v1_budget_url(Budget.date_to_param(target_start)), headers: api_headers(@write_key), as: :json

    assert_response :created
    body = JSON.parse(response.body)
    target = @family.budgets.find(body["id"])
    assert_equal target_start, target.start_date
    assert_equal 300000, body["budgeted_spending_cents"]
    assert_equal 5000, target.expected_income.to_i
    target_category = target.budget_categories.find_by!(category: category)
    assert_equal 250, target_category.budgeted_spending.to_i
    assert target_category.rollover_enabled?
  end

  test "copy previous accepts the web's month param in any case" do
    post copy_previous_api_v1_budget_url(2.months.ago.strftime("%b-%Y").upcase), headers: api_headers(@write_key), as: :json

    assert_response :created
  end

  test "copy previous refuses a month that is already set up" do
    post copy_previous_api_v1_budget_url(Budget.date_to_param(@budget.start_date)), headers: api_headers(@write_key), as: :json

    assert_response :conflict
    assert_equal "already_set_up", JSON.parse(response.body)["error"]
    assert_equal 3000, @budget.reload.budgeted_spending.to_i
  end

  test "copy previous answers no_source when there is nothing earlier to copy" do
    post copy_previous_api_v1_budget_url(Budget.date_to_param(4.months.ago.to_date)), headers: api_headers(@write_key), as: :json

    assert_response :unprocessable_entity
    assert_equal "no_source", JSON.parse(response.body)["error"]
  end

  test "copy previous respects budget sharing" do
    owner = users(:family_member)
    source = personal_budget_for(owner)
    target = @family.budgets.create!(user: owner, start_date: 4.months.ago.beginning_of_month.to_date,
                                     end_date: 4.months.ago.end_of_month.to_date, currency: "USD")
    month_param = Budget.date_to_param(target.start_date)

    post copy_previous_api_v1_budget_url(month_param), params: { owner: owner.id }, headers: api_headers(@write_key), as: :json
    assert_response :not_found

    share = BudgetShare.create!(owner: owner, viewer: @user, permission: "read_only")
    post copy_previous_api_v1_budget_url(month_param), params: { owner: owner.id }, headers: api_headers(@write_key), as: :json
    assert_response :forbidden
    assert_nil target.reload.budgeted_spending

    share.update!(permission: "read_write")
    post copy_previous_api_v1_budget_url(month_param), params: { owner: owner.id }, headers: api_headers(@write_key), as: :json
    assert_response :created
    assert_equal source.budgeted_spending.to_i, target.reload.budgeted_spending.to_i
  end

  test "copy previous returns not found for a malformed month" do
    post copy_previous_api_v1_budget_url("2026-11"), headers: api_headers(@write_key), as: :json

    assert_response :not_found
  end

  test "creating and copying need a read-write key and authentication" do
    read_key = ApiKey.create!(user: @user, name: "Test Read Key", scopes: [ "read" ], source: "mobile",
                              display_key: "test_read_#{SecureRandom.hex(8)}")

    post api_v1_budgets_url, params: { budget: { month: 2.months.from_now.strftime("%Y-%m") } }, headers: api_headers(read_key), as: :json
    assert_response :forbidden
    assert_equal "insufficient_scope", JSON.parse(response.body)["error"]

    post copy_previous_api_v1_budget_url(Budget.date_to_param(2.months.ago.to_date)), headers: api_headers(read_key), as: :json
    assert_response :forbidden

    post api_v1_budgets_url, params: { budget: { month: 2.months.from_now.strftime("%Y-%m") } }, as: :json
    assert_response :unauthorized

    post copy_previous_api_v1_budget_url(Budget.date_to_param(2.months.ago.to_date)), as: :json
    assert_response :unauthorized
  end

  private

    def personal_budget_for(owner)
      @family.update!(personal_budgets: true)
      @family.budgets.create!(
        user: owner,
        start_date: 5.months.ago.beginning_of_month.to_date,
        end_date: 5.months.ago.end_of_month.to_date,
        budgeted_spending: 800,
        currency: "USD"
      )
    end
end
