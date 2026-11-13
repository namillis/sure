# frozen_string_literal: true

require "test_helper"

class Api::V1::AccountAccountablesTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @user.api_keys.active.destroy_all
    @api_key = ApiKey.create!(user: @user, name: "rw key", scopes: [ "read_write" ], source: "web",
      display_key: "rw_#{SecureRandom.hex(8)}")
    @loan_account = accounts(:loan)
  end

  test "show returns loan terms, insurance and rate changes" do
    @loan_account.loan.update!(
      rate_type: "variable", initial_balance: 250_000, start_date: Date.new(2020, 1, 1), down_payment: 50_000,
      insurance_rate: 0.25, insurance_rate_type: "level_term", day_count_convention: "actual_365",
      principal_only_transfers: true,
      rate_changes: [ { effective_date: "2022-01-01", rate: "4.5" }, { effective_date: "2021-01-01", rate: "4" } ]
    )

    get "/api/v1/accounts/#{@loan_account.id}", headers: api_headers

    assert_response :success
    loan = response.parsed_body["accountable"]
    assert_equal "variable", loan["rate_type"]
    assert_equal "3.5", loan["interest_rate"]
    assert_equal 360, loan["term_months"]
    assert_equal "250000.0", loan["initial_balance"]
    assert_equal "2020-01-01", loan["start_date"]
    assert_equal "50000.0", loan["down_payment"]
    assert_equal "0.25", loan["insurance_rate"]
    assert_equal "level_term", loan["insurance_rate_type"]
    assert_equal "actual_365", loan["day_count_convention"]
    assert_equal true, loan["principal_only_transfers"]
    assert_equal [ { "effective_date" => "2021-01-01", "rate" => "4.0" }, { "effective_date" => "2022-01-01", "rate" => "4.5" } ],
      loan["rate_changes"]
  end

  test "index leaves the accountable block out" do
    get "/api/v1/accounts", headers: api_headers

    assert_response :success
    assert response.parsed_body["accounts"].none? { |account| account.key?("accountable") }
  end

  test "rate changes and insurance written as JSON read back the same" do
    @loan_account.loan.update!(start_date: Date.new(2020, 1, 1))
    body = { account: { accountable_attributes: {
      rate_type: "variable", insurance_rate: 0.3, insurance_rate_type: "decreasing_life",
      rate_changes: [ { effective_date: "2023-06-01", rate: 5.125 } ]
    } } }

    patch "/api/v1/accounts/#{@loan_account.id}", params: body, headers: api_headers, as: :json

    assert_response :success, response.body
    loan = response.parsed_body["accountable"]
    assert_equal [ { "effective_date" => "2023-06-01", "rate" => "5.125" } ], loan["rate_changes"]
    assert_equal "0.3", loan["insurance_rate"]
    assert_equal "decreasing_life", loan["insurance_rate_type"]
    assert_equal({ "2023-06-01" => "5.125" }, @loan_account.loan.reload.variable_rate_schedule)
  end

  test "an empty rate_changes list clears the schedule and a missing one keeps it" do
    @loan_account.loan.update!(rate_type: "variable", start_date: Date.new(2020, 1, 1),
      rate_changes: [ { effective_date: "2021-01-01", rate: "4" } ])

    patch "/api/v1/accounts/#{@loan_account.id}", params: { account: { accountable_attributes: { term_months: 240 } } },
      headers: api_headers, as: :json
    assert_response :success
    assert_equal 1, response.parsed_body.dig("accountable", "rate_changes").size

    patch "/api/v1/accounts/#{@loan_account.id}", params: { account: { accountable_attributes: { rate_changes: [] } } },
      headers: api_headers, as: :json
    assert_response :success, response.body
    assert_equal [], response.parsed_body.dig("accountable", "rate_changes")
    assert_equal({}, @loan_account.loan.reload.variable_rate_schedule)
  end

  test "invalid rate changes and insurance are 422" do
    @loan_account.loan.update!(rate_type: "variable", start_date: Date.new(2020, 1, 1))

    [
      { rate_changes: [ { effective_date: "not-a-date", rate: 4 } ] },
      { rate_changes: [ { effective_date: "2021-01-01", rate: 101 } ] },
      { rate_changes: [ { effective_date: "2019-01-01", rate: 4 } ] },
      { insurance_rate_type: "whole_life" },
      { insurance_rate: -1 }
    ].each do |attributes|
      patch "/api/v1/accounts/#{@loan_account.id}", params: { account: { accountable_attributes: attributes } },
        headers: api_headers, as: :json
      assert_response :unprocessable_entity, attributes.inspect
      assert_equal "validation_failed", response.parsed_body["error"]
    end
    assert_equal({}, @loan_account.loan.reload.variable_rate_schedule)
  end

  test "other types return the fields their edit form takes" do
    get "/api/v1/accounts/#{accounts(:credit_card).id}", headers: api_headers
    card = response.parsed_body["accountable"]
    assert_equal "5000.0", card["available_credit"]
    assert_equal "18.99", card["apr"]
    assert card.key?("due_day")

    get "/api/v1/accounts/#{accounts(:vehicle).id}", headers: api_headers
    vehicle = response.parsed_body["accountable"]
    assert_equal %w[initial_balance initial_balance_shown make mileage_unit mileage_value model purchase_date year], vehicle.keys.sort
    assert_equal vehicle["initial_balance"], vehicle["initial_balance_shown"]

    get "/api/v1/accounts/#{accounts(:property).id}", headers: api_headers
    property = response.parsed_body["accountable"]
    assert_equal %w[address_attributes area_unit area_value subtype year_built], property.keys.sort

    get "/api/v1/accounts/#{accounts(:crypto).id}", headers: api_headers
    assert_equal %w[subtype tax_treatment], response.parsed_body["accountable"].keys.sort

    get "/api/v1/accounts/#{accounts(:depository).id}", headers: api_headers
    assert_equal({}, response.parsed_body["accountable"])
  end

  test "vehicle purchase fields round-trip through an edit" do
    account = accounts(:vehicle)
    get "/api/v1/accounts/#{account.id}", headers: api_headers
    shown = response.parsed_body["accountable"]

    patch "/api/v1/accounts/#{account.id}", params: { account: { accountable_attributes: {
      initial_balance: shown["initial_balance"].to_d + 1000, initial_balance_shown: shown["initial_balance_shown"]
    } } }, headers: api_headers, as: :json

    assert_response :success, response.body
    assert_equal (shown["initial_balance"].to_d + 1000), response.parsed_body.dig("accountable", "initial_balance").to_d
  end

  test "requires authentication" do
    get "/api/v1/accounts/#{@loan_account.id}"
    assert_response :unauthorized
  end

  private

    def api_headers
      { "X-Api-Key" => @api_key.plain_key }
    end
end
