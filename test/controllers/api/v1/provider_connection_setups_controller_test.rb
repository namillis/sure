# frozen_string_literal: true

require "test_helper"

class Api::V1::ProviderConnectionSetupsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  SETUP_TOKEN = Base64.strict_encode64("https://bridge.example.com/simplefin/claim/secret-claim-token")
  ACCESS_URL = "https://user:secret-access-password@bridge.example.com/simplefin"

  setup do
    @admin = users(:family_admin)
    @member = users(:family_member)
    @family = @admin.family

    @admin.api_keys.active.destroy_all
    @member.api_keys.active.destroy_all

    @admin_key = create_key(@admin, [ "read_write" ])
    @read_key = create_key(@admin, [ "read" ])
    @member_key = create_key(@member, [ "read_write" ])

    @simplefin_item = @family.simplefin_items.create!(name: "SimpleFIN", access_url: ACCESS_URL)
    @checking = @simplefin_item.simplefin_accounts.create!(
      name: "Everyday Checking", account_id: "sf_checking", account_type: "depository",
      currency: "USD", current_balance: 1234.56, org_data: { "name" => "First Bank" }
    )
    @card = @simplefin_item.simplefin_accounts.create!(
      name: "Rewards Visa", account_id: "sf_card", account_type: "credit", currency: "USD", current_balance: -50
    )
  end

  # --- create ---------------------------------------------------------------

  test "creates a SimpleFIN connection from a setup token" do
    Provider::Simplefin.any_instance.expects(:claim_access_url).with(SETUP_TOKEN).returns(ACCESS_URL)

    assert_difference -> { @family.simplefin_items.count }, 1 do
      assert_enqueued_with(job: SyncJob) do
        post api_v1_provider_connections_url,
          params: { provider: "simplefin", connection: { setup_token: SETUP_TOKEN } },
          headers: api_headers(@admin_key), as: :json
      end
    end

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal "simplefin", json["provider"]
    assert_equal "SimplefinItem", json["provider_type"]
    assert_equal "SimpleFIN Connection", json["name"]
    assert_equal true, json["setup_required"]
    assert_equal true, json["awaiting_accounts"]
    assert_equal [], json["pending_accounts"]
    assert_equal true, json["sync"]["syncing"]
    assert_secrets_absent
  end

  test "an invalid SimpleFIN setup token returns the provider's message without the token" do
    Provider::Simplefin.any_instance.expects(:claim_access_url)
      .raises(Provider::Simplefin::SimplefinError.new("Setup token may be compromised, expired, or already used", :token_compromised))

    assert_no_difference -> { SimplefinItem.count } do
      post api_v1_provider_connections_url,
        params: { provider: "simplefin", connection: { setup_token: SETUP_TOKEN } },
        headers: api_headers(@admin_key), as: :json
    end

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal "token_compromised", json["error"]
    assert_equal I18n.t("simplefin_items.create.errors.token_compromised"), json["message"]
    assert_secrets_absent
  end

  test "a SimpleFIN setup token pointing at a disallowed address is invalid_token" do
    Provider::Simplefin.any_instance.expects(:claim_access_url)
      .raises(Provider::Simplefin::SimplefinError.new("SimpleFIN URL points to a disallowed network address", :invalid_url))

    post api_v1_provider_connections_url,
      params: { provider: "simplefin", connection: { setup_token: SETUP_TOKEN } },
      headers: api_headers(@admin_key), as: :json

    assert_response :unprocessable_entity
    assert_equal "invalid_token", JSON.parse(response.body)["error"]
    assert_secrets_absent
  end

  test "a blank SimpleFIN setup token is rejected before any claim" do
    Provider::Simplefin.any_instance.expects(:claim_access_url).never

    post api_v1_provider_connections_url,
      params: { provider: "simplefin", connection: { setup_token: "" } },
      headers: api_headers(@admin_key), as: :json

    assert_response :unprocessable_entity
    assert_equal "blank_token", JSON.parse(response.body)["error"]
  end

  test "creates a Kraken connection without echoing its credentials" do
    assert_difference -> { @family.kraken_items.count }, 1 do
      post api_v1_provider_connections_url,
        params: { provider: "kraken", connection: { api_key: "kraken-key-abc123", api_secret: "kraken-secret-xyz789" } },
        headers: api_headers(@admin_key), as: :json
    end

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal "kraken", json["provider"]
    assert_equal "Kraken", json["name"]
    assert_equal true, json["credentials_configured"]
    assert_not_includes response.body, "kraken-key-abc123"
    assert_not_includes response.body, "kraken-secret-xyz789"
    assert_equal "kraken.com", @family.kraken_items.order(:created_at).last.institution_domain
  end

  test "missing credentials return validation errors without the submitted values" do
    assert_no_difference -> { KrakenItem.count } do
      post api_v1_provider_connections_url,
        params: { provider: "kraken", connection: { api_key: "kraken-key-abc123" } },
        headers: api_headers(@admin_key), as: :json
    end

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal "validation_failed", json["error"]
    assert json["errors"].any? { |message| message.include?("secret") }
    assert_not_includes response.body, "kraken-key-abc123"
  end

  test "creates a connection for every supported token provider without echoing secrets" do
    {
      "lunchflow" => { api_key: "lf-secret-key-1" },
      "mercury" => { token: "mercury-secret-token-1" },
      "brex" => { token: "  brex-secret-token-1  " },
      "binance" => { api_key: "binance-key-1", api_secret: "binance-secret-1" },
      "coinspot" => { api_key: "coinspot-key-1", api_secret: "coinspot-secret-1" },
      "ibkr" => { query_id: "ibkr-query-1", token: "ibkr-secret-token-1" }
    }.each do |provider, connection|
      post api_v1_provider_connections_url,
        params: { provider: provider, connection: connection.merge(sync_start_date: 1.month.ago.to_date.iso8601) },
        headers: api_headers(@admin_key), as: :json

      assert_response :created, provider
      json = JSON.parse(response.body)
      assert_equal provider, json["provider"]
      assert_equal true, json["setup_required"], provider
      connection.each_value { |secret| assert_not_includes response.body, secret.strip, provider }
    end

    assert_equal "brex-secret-token-1", @family.brex_items.order(:created_at).last.token
  end

  test "providers whose web flow has extra steps are not supported" do
    %w[wise onchain_wallet plaid].each do |provider|
      post api_v1_provider_connections_url,
        params: { provider: provider, connection: { token: "x" } },
        headers: api_headers(@admin_key), as: :json

      assert_response :unprocessable_entity
      assert_equal "provider_not_supported", JSON.parse(response.body)["error"], provider
    end
  end

  test "create requires a provider and a connection object" do
    post api_v1_provider_connections_url, params: { connection: { token: "x" } }, headers: api_headers(@admin_key), as: :json
    assert_response :unprocessable_entity
    assert_equal "validation_failed", JSON.parse(response.body)["error"]

    post api_v1_provider_connections_url, params: { provider: "brex", connection: "x" }, headers: api_headers(@admin_key), as: :json
    assert_response :unprocessable_entity
    assert_equal "validation_failed", JSON.parse(response.body)["error"]
  end

  test "create is admin-only and needs read_write" do
    post api_v1_provider_connections_url,
      params: { provider: "brex", connection: { token: "brex-token" } },
      headers: api_headers(@member_key), as: :json
    assert_response :forbidden
    assert_equal "forbidden", JSON.parse(response.body)["error"]

    post api_v1_provider_connections_url,
      params: { provider: "brex", connection: { token: "brex-token" } },
      headers: api_headers(@read_key), as: :json
    assert_response :forbidden

    post api_v1_provider_connections_url, params: { provider: "brex", connection: { token: "brex-token" } }, as: :json
    assert_response :unauthorized
  end

  # --- pending_accounts -----------------------------------------------------

  test "lists SimpleFIN accounts waiting for setup with the web form's types" do
    get pending_accounts_api_v1_provider_connection_url(@simplefin_item, provider: "simplefin"), headers: api_headers(@read_key)

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal false, json["awaiting_accounts"]
    assert_equal [ @checking.id, @card.id ].sort, json["data"].map { |row| row["id"] }.sort

    checking = json["data"].find { |row| row["id"] == @checking.id }
    assert_equal "Everyday Checking", checking["name"]
    assert_equal "First Bank", checking["institution"]
    assert_equal "$1,234.56", checking["balance"]
    assert_equal 123456, checking["balance_cents"]
    assert_equal "USD", checking["currency"]
    assert checking.key?("suggested_accountable_type")

    types = checking["allowed_types"].map { |type| type["accountable_type"] }
    assert_equal %w[Depository CreditCard Investment Crypto Loan OtherAsset], types
    depository = checking["allowed_types"].find { |type| type["accountable_type"] == "Depository" }
    assert_includes depository["subtypes"].map { |subtype| subtype["value"] }, "savings"
    assert_secrets_absent
  end

  test "linked accounts are not pending" do
    account = Account.create_from_simplefin_account(@checking, "Depository", "checking")
    @checking.update!(account: account)
    @checking.ensure_account_provider!

    get pending_accounts_api_v1_provider_connection_url(@simplefin_item, provider: "simplefin"), headers: api_headers(@read_key)

    assert_equal [ @card.id ], JSON.parse(response.body)["data"].map { |row| row["id"] }
  end

  test "pending accounts fetches Lunch Flow accounts the way the setup page does" do
    lunchflow_item = lunchflow_items(:one)
    lunchflow_item.lunchflow_accounts.destroy_all
    provider = mock("lunchflow_provider")
    provider.expects(:get_accounts).returns(accounts: [
      { id: "lf_1", name: "Joint Checking", currency: "EUR", institution_name: "Test Bank", status: "active" }
    ])
    LunchflowItem.any_instance.stubs(:lunchflow_provider).returns(provider)

    get pending_accounts_api_v1_provider_connection_url(lunchflow_item, provider: "lunchflow"), headers: api_headers(@read_key)

    assert_response :success
    row = JSON.parse(response.body)["data"].sole
    assert_equal "Test Bank - Joint Checking", row["name"]
    assert_equal "EUR", row["currency"]
    assert_nil row["suggested_accountable_type"]
    assert_equal Provider::LunchflowAdapter.supported_account_types.sort, row["allowed_types"].map { |type| type["accountable_type"] }.sort
  end

  test "a provider error while fetching accounts is a 422" do
    lunchflow_item = lunchflow_items(:one)
    lunchflow_item.lunchflow_accounts.destroy_all
    provider = mock("lunchflow_provider")
    provider.expects(:get_accounts).raises(Provider::Lunchflow::LunchflowError.new("Unauthorized"))
    LunchflowItem.any_instance.stubs(:lunchflow_provider).returns(provider)

    get pending_accounts_api_v1_provider_connection_url(lunchflow_item, provider: "lunchflow"), headers: api_headers(@read_key)

    assert_response :unprocessable_entity
    assert_equal "provider_error", JSON.parse(response.body)["error"]
  end

  test "Kraken accounts can only be imported as Crypto" do
    get pending_accounts_api_v1_provider_connection_url(kraken_items(:one), provider: "kraken"), headers: api_headers(@read_key)

    assert_response :success
    row = JSON.parse(response.body)["data"].find { |pending| pending["id"] == kraken_accounts(:one).id }
    assert_equal "Crypto", row["suggested_accountable_type"]
    assert_equal "exchange", row["suggested_subtype"]
    assert_equal [ "Crypto" ], row["allowed_types"].map { |type| type["accountable_type"] }
  end

  test "pending accounts is admin-only" do
    get pending_accounts_api_v1_provider_connection_url(@simplefin_item, provider: "simplefin"), headers: api_headers(@member_key)
    assert_response :forbidden

    get pending_accounts_api_v1_provider_connection_url(@simplefin_item, provider: "simplefin")
    assert_response :unauthorized
  end

  test "another family's connection is not found" do
    other_item = families(:empty).simplefin_items.create!(name: "Other", access_url: ACCESS_URL)

    get pending_accounts_api_v1_provider_connection_url(other_item, provider: "simplefin"), headers: api_headers(@admin_key)
    assert_response :not_found

    post complete_setup_api_v1_provider_connection_url(other_item, provider: "simplefin"),
      params: { accounts: [] }, headers: api_headers(@admin_key), as: :json
    assert_response :not_found
  end

  test "an existing connection of an unsupported provider is provider_not_supported" do
    get pending_accounts_api_v1_provider_connection_url(plaid_items(:one), provider: "plaid"), headers: api_headers(@admin_key)

    assert_response :unprocessable_entity
    assert_equal "provider_not_supported", JSON.parse(response.body)["error"]
  end

  # --- complete_setup -------------------------------------------------------

  test "complete setup creates the chosen SimpleFIN accounts and queues a sync" do
    @simplefin_item.update!(pending_account_setup: true)

    assert_difference -> { @family.accounts.count }, 2 do
      assert_enqueued_with(job: SyncJob) do
        post complete_setup_api_v1_provider_connection_url(@simplefin_item, provider: "simplefin"),
          params: {
            sync_start_date: 1.month.ago.to_date.iso8601,
            accounts: [
              { id: @checking.id, import: true, accountable_type: "Depository", subtype: "savings" },
              { id: @card.id, import: true, accountable_type: "CreditCard" }
            ]
          },
          headers: api_headers(@admin_key), as: :json
      end
    end

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal false, json["setup_required"]
    assert_equal [], json["pending_accounts"]
    assert_equal 2, json["created_account_ids"].size

    checking_account = @checking.reload.account
    assert_equal "Depository", checking_account.accountable_type
    assert_equal "savings", checking_account.accountable.subtype
    assert_equal "credit_card", @card.reload.account.accountable.subtype
    assert_not @simplefin_item.reload.pending_account_setup
    assert_equal 1.month.ago.to_date, @simplefin_item.sync_start_date
    assert_secrets_absent
  end

  test "skipped accounts stay pending" do
    post complete_setup_api_v1_provider_connection_url(@simplefin_item, provider: "simplefin"),
      params: { accounts: [ { id: @checking.id, import: true, accountable_type: "Depository" }, { id: @card.id, import: false } ] },
      headers: api_headers(@admin_key), as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal [ @card.id ], json["pending_accounts"].map { |row| row["id"] }
    assert_nil @card.reload.account
  end

  test "an invalid type or subtype changes nothing" do
    [
      [ { id: @checking.id, import: true, accountable_type: "Property" }, "invalid_account_type" ],
      [ { id: @checking.id, import: true }, "invalid_account_type" ],
      [ { id: @checking.id, import: true, accountable_type: "Depository", subtype: "mortgage" }, "invalid_subtype" ],
      [ { id: SecureRandom.uuid, import: true, accountable_type: "Depository" }, "unknown_account" ],
      [ { id: @checking.id, import: true, accountable_type: "Depository", link_to_account_id: accounts(:depository).id }, "link_not_supported" ]
    ].each do |row, error|
      assert_no_difference -> { Account.count } do
        post complete_setup_api_v1_provider_connection_url(@simplefin_item, provider: "simplefin"),
          params: { accounts: [ { id: @card.id, import: true, accountable_type: "CreditCard" }, row ] },
          headers: api_headers(@admin_key), as: :json
      end

      assert_response :unprocessable_entity
      assert_equal error, JSON.parse(response.body)["error"], row.inspect
    end
  end

  test "complete setup rejects a missing accounts list and a bad sync start date" do
    post complete_setup_api_v1_provider_connection_url(@simplefin_item, provider: "simplefin"),
      params: {}, headers: api_headers(@admin_key), as: :json
    assert_response :unprocessable_entity
    assert_equal "validation_failed", JSON.parse(response.body)["error"]

    post complete_setup_api_v1_provider_connection_url(@simplefin_item, provider: "simplefin"),
      params: { sync_start_date: 1.day.from_now.to_date.iso8601, accounts: [] }, headers: api_headers(@admin_key), as: :json
    assert_response :unprocessable_entity
    assert_equal "invalid_sync_start_date", JSON.parse(response.body)["error"]
  end

  test "complete setup imports selected Kraken accounts as Crypto" do
    kraken_item = kraken_items(:one)
    KrakenAccount::Processor.any_instance.stubs(:process)

    assert_difference -> { @family.accounts.where(accountable_type: "Crypto").count }, 1 do
      post complete_setup_api_v1_provider_connection_url(kraken_item, provider: "kraken"),
        params: { accounts: [ { id: kraken_accounts(:one).id, import: true } ] },
        headers: api_headers(@admin_key), as: :json
    end

    assert_response :success
    assert kraken_accounts(:one).reload.account_provider.present?
    assert_not_includes response.body, kraken_item.api_key
    assert_not_includes response.body, kraken_item.api_secret

    post complete_setup_api_v1_provider_connection_url(kraken_item, provider: "kraken"),
      params: { accounts: [ { id: kraken_accounts(:one).id, import: true } ] },
      headers: api_headers(@admin_key), as: :json
    assert_response :unprocessable_entity
    assert_equal "unknown_account", JSON.parse(response.body)["error"]
  end

  test "complete setup is admin-only and needs read_write" do
    params = { accounts: [ { id: @checking.id, import: true, accountable_type: "Depository" } ] }

    post complete_setup_api_v1_provider_connection_url(@simplefin_item, provider: "simplefin"), params: params, headers: api_headers(@member_key), as: :json
    assert_response :forbidden

    post complete_setup_api_v1_provider_connection_url(@simplefin_item, provider: "simplefin"), params: params, headers: api_headers(@read_key), as: :json
    assert_response :forbidden

    assert_nil @checking.reload.account
  end

  private

    def create_key(user, scopes)
      key = ApiKey.create!(user: user, name: "Test #{scopes.join} key", scopes: scopes,
        display_key: "test_#{SecureRandom.hex(8)}", source: scopes == [ "read" ] ? "web" : "mobile")
      Redis.new.del("api_rate_limit:#{key.id}")
      key
    end

    def api_headers(api_key)
      { "X-Api-Key" => api_key.plain_key }
    end

    def assert_secrets_absent
      [ SETUP_TOKEN, "secret-claim-token", "secret-access-password", ACCESS_URL ].each do |secret|
        assert_not_includes response.body, secret
      end
    end
end
