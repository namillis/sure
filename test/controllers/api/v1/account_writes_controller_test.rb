# frozen_string_literal: true

require "test_helper"

class Api::V1::AccountWritesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @member = users(:family_member)
    @user.api_keys.active.destroy_all
    @member.api_keys.active.destroy_all
    @api_key = api_key_for(@user, "read_write")
    @read_key = api_key_for(@user, "read")
    @member_key = api_key_for(@member, "read_write")
  end

  test "requires authentication" do
    post "/api/v1/accounts", params: { account: { accountable_type: "Depository", name: "X", balance: 1 } }
    assert_response :unauthorized
  end

  test "read-only key cannot create, update or delete" do
    post "/api/v1/accounts", params: { account: { accountable_type: "Depository", name: "X", balance: 1 } },
      headers: api_headers(@read_key)
    assert_response :forbidden
    assert_equal "insufficient_scope", response.parsed_body["error"]

    patch "/api/v1/accounts/#{accounts(:depository).id}", params: { account: { name: "Y" } }, headers: api_headers(@read_key)
    assert_response :forbidden

    delete "/api/v1/accounts/#{accounts(:depository).id}", headers: api_headers(@read_key)
    assert_response :forbidden
  end

  test "creates a depository with subtype and opening balance" do
    assert_difference -> { Account.count } => 1, -> { Depository.count } => 1, -> { Valuation.count } => 1 do
      post "/api/v1/accounts", params: {
        account: {
          accountable_type: "Depository", name: "API Savings", balance: 1234.56, currency: "USD",
          subtype: "savings", institution_name: "Bank", notes: "n", opening_balance_date: "2025-01-01"
        }
      }, headers: api_headers(@api_key)
    end

    assert_response :created
    body = response.parsed_body
    account = Account.find(body["id"])
    assert_equal "API Savings", body["name"]
    assert_equal "depository", body["account_type"]
    assert_equal "savings", body["subtype"]
    assert_equal 123456, body["balance_cents"]
    assert_equal @user, account.owner
    assert_equal Date.new(2025, 1, 1), account.entries.valuations.minimum(:date)
  end

  test "accepts the snake_case account_type spelling" do
    post "/api/v1/accounts", params: { account: { accountable_type: "other_asset", name: "Art", balance: 900 } },
      headers: api_headers(@api_key)
    assert_response :created
    assert_equal "other_asset", response.parsed_body["account_type"]
  end

  test "creates each type with its accountable fields" do
    cases = {
      "CreditCard" => { apr: 19.99, available_credit: 5000, annual_fee: 95, statement_close_day: 5, due_day: 28 },
      "Loan" => { subtype: "mortgage", interest_rate: 5.5, term_months: 360, rate_type: "fixed", initial_balance: 300000 },
      "Investment" => { subtype: "brokerage" },
      "Crypto" => { subtype: "exchange", tax_treatment: "taxable" },
      "Vehicle" => { make: "Toyota", model: "Camry", year: 2020, mileage_value: 12000, mileage_unit: "mi" },
      "OtherLiability" => {}
    }

    cases.each do |type, accountable_attributes|
      post "/api/v1/accounts", params: {
        account: { accountable_type: type, name: "API #{type}", balance: 1000, currency: "USD", accountable_attributes: accountable_attributes }
      }, headers: api_headers(@api_key)
      assert_response :created, "#{type}: #{response.body}"

      accountable = Account.find(response.parsed_body["id"]).accountable
      assert_instance_of type.constantize, accountable
      accountable_attributes.each do |key, value|
        actual = accountable.public_send(key)
        assert_equal value.to_s, actual.is_a?(BigDecimal) ? actual.to_d.to_s.sub(/\.0\z/, "") : actual.to_s, "#{type}.#{key}"
      end
    end
  end

  test "drops accountable fields the web does not permit for the type" do
    post "/api/v1/accounts", params: {
      account: { accountable_type: "Depository", name: "D", balance: 1, accountable_attributes: { apr: 9 } }
    }, headers: api_headers(@api_key)
    assert_response :created
    assert_not Account.find(response.parsed_body["id"]).accountable.respond_to?(:apr)
  end

  test "creates an active property with balance and address" do
    post "/api/v1/accounts", params: {
      account: {
        accountable_type: "Property", name: "Home", balance: 500000, currency: "USD",
        accountable_attributes: {
          subtype: "single_family_home", year_built: 1990, area_value: 2000, area_unit: "sqft",
          address_attributes: { line1: "1 Main St", locality: "Town", region: "CA", postal_code: "90000", country: "US" }
        }
      }
    }, headers: api_headers(@api_key)

    assert_response :created, response.body
    account = Account.find(response.parsed_body["id"])
    assert account.active?
    assert_equal 500000, account.balance
    assert_equal "single_family_home", account.subtype
    assert_equal 1990, account.property.year_built
    assert_equal "1 Main St", account.property.address.line1
  end

  test "property create requires a balance" do
    assert_no_difference -> { Account.count } do
      post "/api/v1/accounts", params: { account: { accountable_type: "Property", name: "Home" } }, headers: api_headers(@api_key)
    end
    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["error"]
  end

  test "rejects an unknown accountable type" do
    post "/api/v1/accounts", params: { account: { accountable_type: "Bogus", name: "X", balance: 1 } }, headers: api_headers(@api_key)
    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["error"]
  end

  test "returns validation errors" do
    assert_no_difference -> { Account.count } do
      post "/api/v1/accounts", params: { account: { accountable_type: "Depository", name: "", balance: 1 } }, headers: api_headers(@api_key)
    end
    assert_response :unprocessable_entity
    body = response.parsed_body
    assert_equal "validation_failed", body["error"]
    assert body["errors"].any?
  end

  test "missing account params is a bad request" do
    post "/api/v1/accounts", params: {}, headers: api_headers(@api_key)
    assert_response :bad_request
  end

  test "updates fields and balance" do
    account = accounts(:depository)
    patch "/api/v1/accounts/#{account.id}", params: {
      account: { name: "Renamed", balance: 6000, subtype: "checking", notes: "hi", exclude_from_reports: true }
    }, headers: api_headers(@api_key)

    assert_response :success, response.body
    account.reload
    assert_equal "Renamed", account.name
    assert_equal 6000, account.balance
    assert_equal "checking", account.subtype
    assert account.exclude_from_reports
    assert_equal "Renamed", response.parsed_body["name"]
  end

  test "updates loan terms" do
    account = accounts(:loan)
    patch "/api/v1/accounts/#{account.id}", params: {
      account: { accountable_type: "Loan", accountable_attributes: { interest_rate: 4.25, term_months: 180 } }
    }, headers: api_headers(@api_key)

    assert_response :success, response.body
    assert_equal 4.25, account.reload.loan.interest_rate.to_f
    assert_equal 180, account.loan.term_months
  end

  test "updates property address and details" do
    account = accounts(:property)
    patch "/api/v1/accounts/#{account.id}", params: {
      account: { accountable_attributes: { year_built: 2001, address_attributes: { line1: "9 Elm", locality: "City" } } }
    }, headers: api_headers(@api_key)

    assert_response :success, response.body
    assert_equal 2001, account.reload.property.year_built
    assert_equal "9 Elm", account.property.address.line1
  end

  test "rejects changing accountable_type" do
    account = accounts(:depository)
    patch "/api/v1/accounts/#{account.id}", params: { account: { accountable_type: "Loan", name: "X" } }, headers: api_headers(@api_key)
    assert_response :unprocessable_entity
    assert_equal "Depository", account.reload.accountable_type
    assert_not_equal "X", account.name
  end

  test "update returns validation errors" do
    patch "/api/v1/accounts/#{accounts(:depository).id}", params: { account: { name: "" } }, headers: api_headers(@api_key)
    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["error"]
  end

  test "linked account allows renaming but not balance or currency" do
    account = accounts(:connected)
    patch "/api/v1/accounts/#{account.id}", params: { account: { name: "My Plaid", notes: "x" } }, headers: api_headers(@api_key)
    assert_response :success
    assert_equal "My Plaid", account.reload.name

    patch "/api/v1/accounts/#{account.id}", params: { account: { balance: 1, currency: "EUR" } }, headers: api_headers(@api_key)
    assert_response :unprocessable_entity
    assert_match "balance, currency", response.parsed_body["message"]
    assert_equal 5000, account.reload.balance
  end

  test "linked accounts cannot be deleted" do
    delete "/api/v1/accounts/#{accounts(:connected).id}", headers: api_headers(@api_key)
    assert_response :unprocessable_entity
    assert accounts(:connected).reload.active?
  end

  test "delete schedules background deletion" do
    account = accounts(:other_asset)
    assert_enqueued_with job: DestroyJob do
      delete "/api/v1/accounts/#{account.id}", headers: api_headers(@api_key)
    end
    assert_response :accepted
    assert_equal account.id, response.parsed_body["id"]
    assert account.reload.pending_deletion?

    delete "/api/v1/accounts/#{account.id}", headers: api_headers(@api_key)
    assert_response :not_found
  end

  test "delete reports a failed enqueue" do
    DestroyJob.queue_adapter.stubs(:enqueue).raises(ActiveJob::EnqueueError, "rejected")
    delete "/api/v1/accounts/#{accounts(:other_asset).id}", headers: api_headers(@api_key)
    assert_response :internal_server_error
    assert accounts(:other_asset).reload.active?
  end

  test "404 for unknown, malformed and other-family accounts" do
    patch "/api/v1/accounts/#{SecureRandom.uuid}", params: { account: { name: "X" } }, headers: api_headers(@api_key)
    assert_response :not_found
    assert_equal "not_found", response.parsed_body["error"]

    delete "/api/v1/accounts/not-a-uuid", headers: api_headers(@api_key)
    assert_response :not_found

    other = users(:empty)
    other.api_keys.active.destroy_all
    patch "/api/v1/accounts/#{accounts(:depository).id}", params: { account: { name: "X" } },
      headers: api_headers(api_key_for(other, "read_write"))
    assert_response :not_found
  end

  test "full-control share can edit and delete" do
    account = accounts(:depository)
    patch "/api/v1/accounts/#{account.id}", params: { account: { name: "Shared edit" } }, headers: api_headers(@member_key)
    assert_response :success
    assert_equal "Shared edit", account.reload.name

    delete "/api/v1/accounts/#{account.id}", headers: api_headers(@member_key)
    assert_response :accepted
  end

  test "read-only share cannot edit or delete" do
    account = accounts(:credit_card)
    patch "/api/v1/accounts/#{account.id}", params: { account: { name: "Nope" } }, headers: api_headers(@member_key)
    assert_response :forbidden
    assert_equal "forbidden", response.parsed_body["error"]

    delete "/api/v1/accounts/#{account.id}", headers: api_headers(@member_key)
    assert_response :forbidden
    assert account.reload.active?
  end

  test "unshared family account is not found for a member" do
    patch "/api/v1/accounts/#{accounts(:loan).id}", params: { account: { name: "X" } }, headers: api_headers(@member_key)
    assert_response :not_found
  end

  test "member creates an account they own" do
    post "/api/v1/accounts", params: { account: { accountable_type: "Crypto", name: "Wallet", balance: 10 } },
      headers: api_headers(@member_key)
    assert_response :created
    assert_equal @member, Account.find(response.parsed_body["id"]).owner
  end

  private

    def api_key_for(user, scope)
      ApiKey.create!(user: user, name: "#{scope} key", scopes: [ scope ], source: "web",
        display_key: "#{scope}_#{SecureRandom.hex(8)}")
    end

    def api_headers(api_key)
      { "X-Api-Key" => api_key.plain_key }
    end
end
