# frozen_string_literal: true

require "test_helper"

class Api::V1::ChartSeriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @member = users(:family_member)
    [ @user, @member ].each { |user| user.api_keys.active.destroy_all }
    @read_key = create_key(@user, [ "read" ])
    @account = accounts(:depository)
  end

  test "net worth series requires authentication" do
    get "/api/v1/net_worth_series"
    assert_response :unauthorized
  end

  test "net worth series requires read scope" do
    @read_key.update_columns(scopes: [])
    get "/api/v1/net_worth_series", headers: api_headers(@read_key)
    assert_response :forbidden
  end

  test "net worth series defaults to the last 30 days and matches the web series" do
    get "/api/v1/net_worth_series", headers: api_headers(@read_key)

    assert_response :success
    body = JSON.parse(response.body)
    period = Period.last_30_days
    expected = @family.balance_sheet(user: @user).net_worth_series(period: period)

    assert_equal "last_30_days", body["period"]
    assert_equal period.start_date.iso8601, body["start_date"]
    assert_equal period.end_date.iso8601, body["end_date"]
    assert_equal "1 day", body["interval"]
    assert_equal @family.currency, body["currency"]
    assert_equal expected.values.size, body["values"].size
    assert_equal expected.values.first.date.iso8601, body["values"].first["date"]
    last_value = expected.values.last.value.for_display
    assert_equal last_value.format, body["values"].last["value"]
    assert_equal (last_value.amount * 100).round.to_i, body["values"].last["value_cents"]
    assert_equal %w[direction favorable_direction percent percent_formatted value value_cents], body["trend"].keys.sort
    assert_includes response.headers["Cache-Control"], "private"
    assert response.headers["ETag"].present?
  end

  test "net worth series accepts every period key" do
    Period::PERIODS.each_key do |key|
      get "/api/v1/net_worth_series", params: { period: key }, headers: api_headers(@read_key)
      assert_response :success, "period #{key}"
      assert_equal key, JSON.parse(response.body)["period"]
    end
  end

  test "all time starts one month before the family's earliest activity, not the 5-year fallback" do
    expected_start = @family.earliest_activity_date - 1.month

    get "/api/v1/net_worth_series", params: { period: "all_time" }, headers: api_headers(@read_key)

    assert_response :success
    assert_equal expected_start.iso8601, JSON.parse(response.body)["start_date"]
    assert_not_equal 5.years.ago.to_date.iso8601, JSON.parse(response.body)["start_date"]
  end

  test "custom dates override period" do
    get "/api/v1/net_worth_series", params: { period: "last_7_days", start_date: 20.days.ago.to_date.iso8601,
      end_date: 10.days.ago.to_date.iso8601 }, headers: api_headers(@read_key)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "custom", body["period"]
    assert_equal 20.days.ago.to_date.iso8601, body["start_date"]
    assert_equal 10.days.ago.to_date.iso8601, body["end_date"]
    assert_equal 11, body["values"].size
  end

  test "invalid period and dates return 422" do
    get "/api/v1/net_worth_series", params: { period: "forever" }, headers: api_headers(@read_key)
    assert_response :unprocessable_entity
    assert_equal "invalid_period", JSON.parse(response.body)["error"]

    get "/api/v1/net_worth_series", params: { start_date: "nope", end_date: "2026-01-01" }, headers: api_headers(@read_key)
    assert_response :unprocessable_entity
    assert_equal "invalid_date", JSON.parse(response.body)["error"]

    get "/api/v1/net_worth_series", params: { start_date: "2026-02-01", end_date: "2026-01-01" }, headers: api_headers(@read_key)
    assert_response :unprocessable_entity

    get "/api/v1/net_worth_series", params: { start_date: "2026-02-01" }, headers: api_headers(@read_key)
    assert_response :unprocessable_entity
  end

  test "matching ETag returns 304 with no body" do
    get "/api/v1/net_worth_series", params: { period: "last_90_days" }, headers: api_headers(@read_key)
    etag = response.headers["ETag"]

    get "/api/v1/net_worth_series", params: { period: "last_90_days" },
      headers: api_headers(@read_key).merge("If-None-Match" => etag)

    assert_response :not_modified
    assert_empty response.body
  end

  test "ETag changes when the family's data changes" do
    get "/api/v1/net_worth_series", headers: api_headers(@read_key)
    etag = response.headers["ETag"]

    @family.touch(:latest_sync_completed_at) if @family.has_attribute?(:latest_sync_completed_at)
    @account.entries.create!(name: "New valuation", date: Date.current, amount: 1, currency: "USD",
      entryable: Valuation.new(kind: "reconciliation"))

    get "/api/v1/net_worth_series", headers: api_headers(@read_key).merge("If-None-Match" => etag)
    assert_response :success
  end

  test "family with no accounts gets empty values and no trend" do
    empty_user = users(:empty)
    empty_user.api_keys.active.destroy_all

    get "/api/v1/net_worth_series", headers: api_headers(create_key(empty_user, [ "read" ]))

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [], body["values"]
    assert_nil body["trend"]
  end

  test "account balance series returns the account's series" do
    get "/api/v1/accounts/#{@account.id}/balance_series", params: { period: "last_90_days" }, headers: api_headers(@read_key)

    assert_response :success
    body = JSON.parse(response.body)
    expected = @account.balance_series(period: Period.last_90_days)
    assert_equal @account.id, body["account_id"]
    assert_equal "balance", body["view"]
    assert_equal @account.currency, body["currency"]
    assert_equal expected.values.size, body["values"].size
    assert_equal expected.values.last.value.for_display.format, body["values"].last["value"]
    assert response.headers["ETag"].present?
  end

  test "account balance series accepts cash and holdings views and rejects others" do
    investment = accounts(:investment)
    %w[cash_balance holdings_balance].each do |view|
      get "/api/v1/accounts/#{investment.id}/balance_series", params: { view: view }, headers: api_headers(@read_key)
      assert_response :success
      assert_equal view, JSON.parse(response.body)["view"]
    end

    get "/api/v1/accounts/#{investment.id}/balance_series", params: { view: "gains" }, headers: api_headers(@read_key)
    assert_response :unprocessable_entity
    assert_equal "invalid_view", JSON.parse(response.body)["error"]
  end

  test "account balance series supports all time and custom dates" do
    get "/api/v1/accounts/#{@account.id}/balance_series", params: { period: "all_time" }, headers: api_headers(@read_key)
    assert_response :success
    assert_equal (@family.earliest_activity_date - 1.month).iso8601, JSON.parse(response.body)["start_date"]

    get "/api/v1/accounts/#{@account.id}/balance_series",
      params: { start_date: 5.days.ago.to_date.iso8601, end_date: Date.current.iso8601 }, headers: api_headers(@read_key)
    assert_response :success
    assert_equal 6, JSON.parse(response.body)["values"].size
  end

  test "account balance series returns 304 on a matching ETag" do
    get "/api/v1/accounts/#{@account.id}/balance_series", headers: api_headers(@read_key)
    etag = response.headers["ETag"]

    get "/api/v1/accounts/#{@account.id}/balance_series", headers: api_headers(@read_key).merge("If-None-Match" => etag)
    assert_response :not_modified
  end

  test "account balance series includes disabled accounts" do
    @account.disable!

    get "/api/v1/accounts/#{@account.id}/balance_series", headers: api_headers(@read_key)
    assert_response :success
  end

  test "another family's account returns 404" do
    other_account = families(:empty).accounts.create!(name: "Other", balance: 10, currency: "USD", accountable: Depository.new,
      owner: users(:empty))

    get "/api/v1/accounts/#{other_account.id}/balance_series", headers: api_headers(@read_key)
    assert_response :not_found
    assert_equal "not_found", JSON.parse(response.body)["error"]
  end

  test "a member sees an account shared with them but not a private one" do
    member_key = create_key(@member, [ "read" ])
    private_account = @family.accounts.create!(name: "Admin private", balance: 10, currency: "USD",
      accountable: Depository.new, owner: @user)

    get "/api/v1/accounts/#{@account.id}/balance_series", headers: api_headers(member_key)
    assert_response :success

    get "/api/v1/accounts/#{private_account.id}/balance_series", headers: api_headers(member_key)
    assert_response :not_found
  end

  test "account balance series requires authentication and read scope" do
    get "/api/v1/accounts/#{@account.id}/balance_series"
    assert_response :unauthorized

    @read_key.update_columns(scopes: [])
    get "/api/v1/accounts/#{@account.id}/balance_series", headers: api_headers(@read_key)
    assert_response :forbidden
  end

  private
    def create_key(user, scopes)
      ApiKey.create!(user: user, name: "Chart key #{SecureRandom.hex(4)}", scopes: scopes, source: "web",
        display_key: "chart_#{SecureRandom.hex(12)}").tap { |key| Redis.new.del("api_rate_limit:#{key.id}") }
    end

    def api_headers(api_key)
      { "X-Api-Key" => api_key.display_key }
    end
end
