# frozen_string_literal: true

require "test_helper"

class Api::V1::TransactionRecurringMarksControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    @user = users(:empty)
    @family = @user.family
    @user.api_keys.active.destroy_all
    @api_key = create_key(@user, [ "read_write" ])

    @account = @family.accounts.create!(name: "Test", balance: 0, currency: "USD", accountable: Depository.new, owner: @user)
    @merchant = @family.merchants.create!(name: "Test Merchant")
    @entry = create_transaction(account: @account, amount: 100, merchant: @merchant)
    @transaction = @entry.entryable
  end

  test "creates a manual recurring transaction" do
    assert_difference("@family.recurring_transactions.count", 1) do
      post mark_as_recurring_api_v1_transaction_url(@transaction), headers: api_headers(@api_key)
    end
    assert_response :created

    body = JSON.parse(response.body)
    recurring = @family.recurring_transactions.find(body["id"])
    assert recurring.manual
    assert_equal @merchant.id, recurring.merchant_id
    assert_equal @entry.date.day, body["expected_day_of_month"]
  end

  test "returns 409 with the series that already covers the transaction" do
    existing = @family.recurring_transactions.create!(
      account: @account, merchant: @merchant, amount: @entry.amount, currency: @entry.currency,
      expected_day_of_month: @entry.date.day, last_occurrence_date: @entry.date,
      next_expected_date: 1.month.from_now, status: "active", manual: true, occurrence_count: 1
    )

    assert_no_difference("RecurringTransaction.count") do
      post mark_as_recurring_api_v1_transaction_url(@transaction), headers: api_headers(@api_key)
    end
    assert_response :conflict

    body = JSON.parse(response.body)
    assert_equal "conflict", body["error"]
    assert_equal I18n.t("recurring_transactions.already_covered"), body["message"]
    assert_equal existing.id, body["recurring_transaction"]["id"]
  end

  test "returns 409 when an ended series holds the same identity" do
    ended = RecurringTransaction.create_from_transaction(@transaction)
    ended.update!(status: "ended")

    post mark_as_recurring_api_v1_transaction_url(@transaction), headers: api_headers(@api_key)
    assert_response :conflict

    body = JSON.parse(response.body)
    assert_equal I18n.t("recurring_transactions.already_exists"), body["message"]
    assert_equal ended.id, body["recurring_transaction"]["id"]
  end

  test "returns 409 when a concurrent request wins the race" do
    RecurringTransaction.expects(:create_from_transaction).raises(ActiveRecord::RecordNotUnique.new("duplicate"))

    post mark_as_recurring_api_v1_transaction_url(@transaction), headers: api_headers(@api_key)
    assert_response :conflict
    assert_equal "conflict", JSON.parse(response.body)["error"]
  end

  test "returns 422 when the series is invalid" do
    RecurringTransaction.expects(:create_from_transaction).raises(ActiveRecord::RecordInvalid.new(RecurringTransaction.new))

    post mark_as_recurring_api_v1_transaction_url(@transaction), headers: api_headers(@api_key)
    assert_response :unprocessable_entity
    assert_equal "validation_failed", JSON.parse(response.body)["error"]
  end

  test "a read-only share returns 403" do
    viewer = @family.users.create!(email: "viewer-#{SecureRandom.hex(4)}@example.com", password: user_password_test,
                                   first_name: "View", last_name: "Er", role: "member", onboarded_at: Time.current)
    @account.account_shares.create!(user: viewer, permission: "read_only")
    key = create_key(viewer, [ "read_write" ])

    assert_no_difference("RecurringTransaction.count") do
      post mark_as_recurring_api_v1_transaction_url(@transaction), headers: api_headers(key)
    end
    assert_response :forbidden
    assert_equal "forbidden", JSON.parse(response.body)["error"]
  end

  test "a read key returns 403" do
    key = create_key(@user, [ "read" ], source: "mobile")

    post mark_as_recurring_api_v1_transaction_url(@transaction), headers: api_headers(key)
    assert_response :forbidden
    assert_equal "insufficient_scope", JSON.parse(response.body)["error"]
  end

  test "returns 401 without an API key" do
    post mark_as_recurring_api_v1_transaction_url(@transaction)
    assert_response :unauthorized
  end

  test "another family's transaction returns 404" do
    other = create_transaction(account: accounts(:depository), amount: 100)

    assert_no_difference("RecurringTransaction.count") do
      post mark_as_recurring_api_v1_transaction_url(other.entryable), headers: api_headers(@api_key)
    end
    assert_response :not_found
  end

  private

    def create_key(user, scopes, source: "web")
      key = ApiKey.create!(user: user, name: "Key #{SecureRandom.hex(4)}", scopes: scopes,
                           display_key: "test_#{SecureRandom.hex(8)}", source: source)
      Redis.new.del("api_rate_limit:#{key.id}")
      key
    end
end
