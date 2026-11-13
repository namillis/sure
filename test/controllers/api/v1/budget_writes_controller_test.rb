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
