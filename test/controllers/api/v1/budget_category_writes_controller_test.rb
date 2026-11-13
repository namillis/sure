# frozen_string_literal: true

require "test_helper"

class Api::V1::BudgetCategoryWritesControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    @user = users(:family_admin)
    @user.api_keys.active.destroy_all

    @write_key = ApiKey.create!(
      user: @user,
      name: "Test Write Key",
      scopes: [ "read_write" ],
      source: "web",
      display_key: "test_rw_#{SecureRandom.hex(8)}"
    )

    @budget = budgets(:one)
    @family = @budget.family

    @parent_category = Category.create!(name: "Bills API test", family: @family, color: "#4da568", lucide_icon: "house")
    @electric_category = Category.create!(name: "Electric API test", parent: @parent_category, family: @family)
    @water_category = Category.create!(name: "Water API test", parent: @parent_category, family: @family)

    @parent_budget_category = @budget.budget_categories.create!(category: @parent_category, budgeted_spending: 500, currency: "USD")
    @electric_budget_category = @budget.budget_categories.create!(category: @electric_category, budgeted_spending: 100, currency: "USD")
    @water_budget_category = @budget.budget_categories.create!(category: @water_category, budgeted_spending: 50, currency: "USD")
  end

  test "updates budgeted spending and returns the budget category" do
    patch api_v1_budget_category_url(@parent_budget_category.id),
          params: { budget_category: { budgeted_spending: "650.25" } },
          headers: api_headers(@write_key),
          as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @parent_budget_category.id, body["id"]
    assert_equal 65025, body["budgeted_spending_cents"]
    assert body.key?("available_to_spend_cents")
    assert_equal @parent_category.id, body.dig("category", "id")
    assert_equal 650.25, @parent_budget_category.reload.budgeted_spending.to_f
  end

  test "updating a subcategory keeps the parent total in sync" do
    patch api_v1_budget_category_url(@electric_budget_category.id),
          params: { budget_category: { budgeted_spending: 200 } },
          headers: api_headers(@write_key),
          as: :json

    assert_response :success
    assert_equal 600, @parent_budget_category.reload.budgeted_spending.to_i
  end

  test "a blank amount clears the allocation like the web form" do
    patch api_v1_budget_category_url(@water_budget_category.id),
          params: { budget_category: { budgeted_spending: "" } },
          headers: api_headers(@write_key),
          as: :json

    assert_response :success
    assert_equal 0, @water_budget_category.reload.budgeted_spending.to_i
  end

  test "toggling rollover alone keeps the allocation, propagates forward and recomputes the chain" do
    previous_budget = Budget.find_or_bootstrap(@family, start_date: 1.month.ago)
    previous_budget.update!(budgeted_spending: 5000, expected_income: 7000)
    previous_budget_category = previous_budget.budget_categories.find_by!(category: @parent_category)
    previous_budget_category.update!(budgeted_spending: 400)

    create_transaction(date: previous_budget.start_date, account: accounts(:depository), amount: 150, category: @parent_category)

    patch api_v1_budget_category_url(previous_budget_category.id),
          params: { budget_category: { rollover_enabled: true } },
          headers: api_headers(@write_key),
          as: :json

    assert_response :success
    assert_equal true, JSON.parse(response.body)["rollover_enabled"]
    assert_equal 400, previous_budget_category.reload.budgeted_spending.to_i
    assert @parent_budget_category.reload.rollover_enabled?
    assert_equal 250.0, @parent_budget_category[:rolled_over_amount].to_f

    patch api_v1_budget_category_url(previous_budget_category.id),
          params: { budget_category: { rollover_enabled: "0" } },
          headers: api_headers(@write_key),
          as: :json

    assert_response :success
    assert_not @parent_budget_category.reload.rollover_enabled?
    assert_equal 0.0, @parent_budget_category[:rolled_over_amount].to_f
  end

  test "rejects invalid values" do
    patch api_v1_budget_category_url(@parent_budget_category.id),
          params: { budget_category: { budgeted_spending: -5 } },
          headers: api_headers(@write_key),
          as: :json

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "validation_failed", body["error"]
    assert_includes body["errors"], "budgeted_spending must be a number greater than or equal to 0"

    patch api_v1_budget_category_url(@parent_budget_category.id),
          params: { budget_category: { rollover_enabled: "maybe", budgeted_spending: 10 } },
          headers: api_headers(@write_key),
          as: :json

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"], "rollover_enabled must be true or false"

    patch api_v1_budget_category_url(@parent_budget_category.id),
          params: { budget_category: { category_id: @water_category.id } },
          headers: api_headers(@write_key),
          as: :json

    assert_response :unprocessable_entity

    @parent_budget_category.reload
    assert_equal 500, @parent_budget_category.budgeted_spending.to_i
    assert_not @parent_budget_category.rollover_enabled?
  end

  test "returns not found outside the family and for invalid ids" do
    other_family = families(:empty)
    other_category = other_family.categories.create!(name: "Other Food", color: "#123456")
    other_budget = other_family.budgets.create!(
      start_date: 6.months.ago.beginning_of_month.to_date,
      end_date: 6.months.ago.end_of_month.to_date,
      budgeted_spending: 1000,
      currency: "USD"
    )
    other_budget_category = other_budget.budget_categories.create!(category: other_category, budgeted_spending: 100, currency: "USD")

    patch api_v1_budget_category_url(other_budget_category.id), params: { budget_category: { budgeted_spending: 1 } },
          headers: api_headers(@write_key), as: :json
    assert_response :not_found
    assert_equal 100, other_budget_category.reload.budgeted_spending.to_i

    patch api_v1_budget_category_url("not-a-uuid"), params: { budget_category: { budgeted_spending: 1 } },
          headers: api_headers(@write_key), as: :json
    assert_response :not_found
  end

  test "respects personal budget sharing" do
    owner = users(:family_member)
    member_budget_category = personal_budget_category_for(owner)

    patch api_v1_budget_category_url(member_budget_category.id), params: { budget_category: { budgeted_spending: 1 } },
          headers: api_headers(@write_key), as: :json
    assert_response :not_found

    share = BudgetShare.create!(owner: owner, viewer: @user, permission: "read_only")
    patch api_v1_budget_category_url(member_budget_category.id), params: { budget_category: { budgeted_spending: 1 } },
          headers: api_headers(@write_key), as: :json
    assert_response :forbidden
    assert_equal 300, member_budget_category.reload.budgeted_spending.to_i

    share.update!(permission: "read_write")
    patch api_v1_budget_category_url(member_budget_category.id), params: { budget_category: { budgeted_spending: 350 } },
          headers: api_headers(@write_key), as: :json
    assert_response :success
    assert_equal 350, member_budget_category.reload.budgeted_spending.to_i
  end

  test "requires authentication" do
    patch api_v1_budget_category_url(@parent_budget_category.id), params: { budget_category: { budgeted_spending: 1 } }, as: :json

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

    patch api_v1_budget_category_url(@parent_budget_category.id), params: { budget_category: { budgeted_spending: 1 } },
          headers: api_headers(read_key), as: :json

    assert_response :forbidden
    assert_equal "insufficient_scope", JSON.parse(response.body)["error"]
    assert_equal 500, @parent_budget_category.reload.budgeted_spending.to_i
  end

  test "moves allocation between categories and returns both rows with the budget" do
    food = Category.create!(name: "Food API move", family: @family, color: "#111111")
    food_budget_category = @budget.budget_categories.create!(category: food, budgeted_spending: 40, currency: "USD")

    post move_api_v1_budget_budget_categories_url(@budget.id),
         params: { move: { from_id: @water_budget_category.id, to_id: food_budget_category.id, amount: "30" } },
         headers: api_headers(@write_key), as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @water_budget_category.id, body.dig("from", "id")
    assert_equal 2000, body.dig("from", "budgeted_spending_cents")
    assert_equal food_budget_category.id, body.dig("to", "id")
    assert_equal 7000, body.dig("to", "budgeted_spending_cents")
    assert body["from"].key?("available_to_spend_cents")
    assert_equal @budget.id, body.dig("budget", "id")
    assert body["budget"].key?("available_to_allocate_cents")
    assert_equal 20, @water_budget_category.reload.budgeted_spending.to_i
    assert_equal 470, @parent_budget_category.reload.budgeted_spending.to_i
  end

  test "refuses a move larger than the source allocation and leaves both rows alone" do
    post move_api_v1_budget_budget_categories_url(@budget.id),
         params: { move: { from_id: @water_budget_category.id, to_id: @electric_budget_category.id, amount: 51 } },
         headers: api_headers(@write_key), as: :json

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "validation_failed", body["error"]
    assert_equal "insufficient_funds", body["reason"]
    assert_equal I18n.t("budget_categories.move.errors.insufficient_funds"), body["message"]
    assert_equal 50, @water_budget_category.reload.budgeted_spending.to_i
    assert_equal 100, @electric_budget_category.reload.budgeted_spending.to_i
  end

  test "refuses a move between different budgets" do
    other_budget = Budget.find_or_bootstrap(@family, start_date: 1.month.ago)
    other_budget_category = other_budget.budget_categories.find_by!(category: @water_category)

    post move_api_v1_budget_budget_categories_url(@budget.id),
         params: { move: { from_id: @water_budget_category.id, to_id: other_budget_category.id, amount: 10 } },
         headers: api_headers(@write_key), as: :json

    assert_response :unprocessable_entity
    assert_equal "different_budgets", JSON.parse(response.body)["reason"]
    assert_equal 50, @water_budget_category.reload.budgeted_spending.to_i
  end

  test "refuses a zero or malformed move amount" do
    [ 0, "-5", "abc", nil ].each do |bad_amount|
      post move_api_v1_budget_budget_categories_url(@budget.id),
           params: { move: { from_id: @water_budget_category.id, to_id: @electric_budget_category.id, amount: bad_amount } },
           headers: api_headers(@write_key), as: :json

      assert_response :unprocessable_entity
      assert_equal "validation_failed", JSON.parse(response.body)["error"]
    end
  end

  test "move returns not found for unknown budgets and categories" do
    post move_api_v1_budget_budget_categories_url("not-a-uuid"),
         params: { move: { from_id: @water_budget_category.id, to_id: @electric_budget_category.id, amount: 1 } },
         headers: api_headers(@write_key), as: :json
    assert_response :not_found

    post move_api_v1_budget_budget_categories_url(@budget.id),
         params: { move: { from_id: SecureRandom.uuid, to_id: @electric_budget_category.id, amount: 1 } },
         headers: api_headers(@write_key), as: :json
    assert_response :not_found
  end

  test "move respects personal budget sharing" do
    owner = users(:family_member)
    member_budget_category = personal_budget_category_for(owner)
    member_budget = member_budget_category.budget
    unrelated = Category.create!(name: "Travel API move", family: @family, color: "#222222")
    other = member_budget.budget_categories.create!(category: unrelated, budgeted_spending: 0, currency: "USD")
    move = { move: { from_id: member_budget_category.id, to_id: other.id, amount: 10 } }

    post move_api_v1_budget_budget_categories_url(member_budget.id), params: move, headers: api_headers(@write_key), as: :json
    assert_response :not_found

    share = BudgetShare.create!(owner: owner, viewer: @user, permission: "read_only")
    post move_api_v1_budget_budget_categories_url(member_budget.id), params: move, headers: api_headers(@write_key), as: :json
    assert_response :forbidden
    assert_equal 300, member_budget_category.reload.budgeted_spending.to_i

    share.update!(permission: "read_write")
    post move_api_v1_budget_budget_categories_url(member_budget.id), params: move, headers: api_headers(@write_key), as: :json
    assert_response :success
    assert_equal 290, member_budget_category.reload.budgeted_spending.to_i
  end

  test "move needs a read-write key and authentication" do
    read_key = ApiKey.create!(user: @user, name: "Test Read Key", scopes: [ "read" ], source: "mobile",
                              display_key: "test_read_#{SecureRandom.hex(8)}")
    move = { move: { from_id: @water_budget_category.id, to_id: @electric_budget_category.id, amount: 1 } }

    post move_api_v1_budget_budget_categories_url(@budget.id), params: move, headers: api_headers(read_key), as: :json
    assert_response :forbidden
    assert_equal "insufficient_scope", JSON.parse(response.body)["error"]

    post move_api_v1_budget_budget_categories_url(@budget.id), params: move, as: :json
    assert_response :unauthorized
    assert_equal 50, @water_budget_category.reload.budgeted_spending.to_i
  end

  private

    def personal_budget_category_for(owner)
      @family.update!(personal_budgets: true)
      member_budget = @family.budgets.create!(
        user: owner,
        start_date: 5.months.ago.beginning_of_month.to_date,
        end_date: 5.months.ago.end_of_month.to_date,
        budgeted_spending: 800,
        currency: "USD"
      )
      member_budget.budget_categories.create!(category: @parent_category, budgeted_spending: 300, currency: "USD")
    end
end
