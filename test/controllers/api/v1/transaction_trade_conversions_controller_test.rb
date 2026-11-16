# frozen_string_literal: true

require "test_helper"

class Api::V1::TransactionTradeConversionsControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    @user = users(:family_admin)
    @account = accounts(:investment)
    @entry = create_transaction(account: @account, amount: 100, name: "Bought AAPL")
    @transaction = @entry.transaction

    @user.api_keys.active.destroy_all
    @api_key = create_key(@user, [ "read_write" ])
    @read_only_api_key = create_key(@user, [ "read" ], source: "mobile")
  end

  def create_key(user, scopes, source: "web")
    key = ApiKey.create!(user: user, name: "Key #{SecureRandom.hex(3)}", scopes: scopes,
                         display_key: "test_#{SecureRandom.hex(8)}", source: source)
    Redis.new.del("api_rate_limit:#{key.id}")
    key
  end

  def convert(params, key: @api_key, transaction: @transaction)
    post convert_to_trade_api_v1_transaction_url(transaction), params: { trade: params },
         headers: api_headers(key), as: :json
  end

  def json
    JSON.parse(response.body)
  end

  # GET

  test "returns the form defaults" do
    get convert_to_trade_api_v1_transaction_url(@transaction), headers: api_headers(@read_only_api_key)
    assert_response :success

    assert_equal @transaction.id, json["transaction_id"]
    assert_equal 10000, json["amount_cents"]
    assert_equal "USD", json["currency"]
    assert_equal({ "id" => @account.id, "name" => @account.name, "account_type" => "investment" }, json["account"])
    assert_equal({ "investment_activity_label" => "Buy", "security_id" => nil, "qty" => nil, "price" => nil },
                 json["defaults"])
    assert_equal %w[Buy Sell], json["investment_activity_labels"]
    assert_includes [ true, false ], json["ticker_search_available"]

    aapl = json["security_options"].find { |option| option["id"] == securities(:aapl).id }
    assert_equal "AAPL", aapl["ticker"]
    assert_equal "XNAS", aapl["exchange_operating_mic"]
  end

  test "suggests a sell for money coming in" do
    @entry.update!(amount: -100)
    get convert_to_trade_api_v1_transaction_url(@transaction), headers: api_headers(@api_key)
    assert_response :success
    assert_equal "Sell", json["defaults"]["investment_activity_label"]
  end

  test "GET returns 422 for an account that cannot hold trades or an excluded transaction" do
    depository_entry = create_transaction(account: accounts(:depository))
    get convert_to_trade_api_v1_transaction_url(depository_entry.transaction), headers: api_headers(@api_key)
    assert_response :unprocessable_entity
    assert_equal "not_investment_account", json["error"]

    @entry.update!(excluded: true)
    get convert_to_trade_api_v1_transaction_url(@transaction), headers: api_headers(@api_key)
    assert_response :unprocessable_entity
    assert_equal "already_converted", json["error"]
  end

  # POST

  test "converts the transaction into a trade and excludes it" do
    assert_difference "Trade.count", 1 do
      convert({ security_id: securities(:aapl).id, qty: 2, price: 50, investment_activity_label: "Buy" })
    end
    assert_response :created

    trade = Trade.find(json["id"])
    assert_equal 2, trade.qty
    assert_equal 50, trade.price
    assert_equal "Buy", trade.investment_activity_label
    assert_equal 100, trade.entry.amount
    assert_equal @entry.date, trade.entry.date
    assert trade.entry.user_modified?
    assert @entry.reload.excluded?

    assert_equal "Buy", json["investment_activity_label"]
    assert_equal "AAPL", json["security"]["ticker"]
    assert_equal @account.id, json["account"]["id"]
  end

  test "infers the price and a sell from the amount" do
    @entry.update!(amount: -200)

    convert({ security_id: securities(:aapl).id, qty: 4 })
    assert_response :created

    trade = Trade.find(json["id"])
    assert_equal(-4, trade.qty)
    assert_equal 50, trade.price
    assert_equal "Sell", trade.investment_activity_label
    assert_equal(-200, trade.entry.amount)
  end

  test "accepts a custom ticker" do
    Security::Resolver.any_instance.expects(:resolve).returns(securities(:msft))

    convert({ custom_ticker: "MSFT", price: 25 })
    assert_response :created
    assert_equal "MSFT", json["security"]["ticker"]
    assert_equal "4.0", Trade.find(json["id"]).qty.to_s
  end

  test "returns 422 with the web's message for invalid input" do
    [
      [ { qty: 2 }, "select_security" ],
      [ { security_id: SecureRandom.uuid, qty: 2 }, "security_not_found" ],
      [ { ticker: "|XNAS", qty: 2 }, "enter_ticker" ],
      [ { security_id: securities(:aapl).id }, "enter_qty_or_price" ],
      [ { security_id: securities(:aapl).id, qty: 0, price: 50 }, "invalid_qty_or_price" ]
    ].each do |params, key|
      assert_no_difference "Trade.count" do
        convert(params)
      end
      assert_response :unprocessable_entity
      assert_equal key, json["error"], params.inspect
      assert_equal I18n.t("transactions.convert_to_trade.errors.#{key}"), json["message"]
      assert_equal [ json["message"] ], json["errors"]
      assert_not @entry.reload.excluded?
    end
  end

  test "rejects an activity label the form does not offer" do
    assert_no_difference "Trade.count" do
      convert({ security_id: securities(:aapl).id, qty: 2, investment_activity_label: "Dividend" })
    end
    assert_response :unprocessable_entity
    assert_equal "validation_failed", json["error"]
  end

  test "an excluded transaction cannot be converted again" do
    convert({ security_id: securities(:aapl).id, qty: 2 })
    assert_response :created

    assert_no_difference "Trade.count" do
      convert({ security_id: securities(:aapl).id, qty: 2 })
    end
    assert_response :unprocessable_entity
    assert_equal "already_converted", json["error"]
  end

  test "an account that cannot hold trades returns 422" do
    depository_entry = create_transaction(account: accounts(:depository))

    assert_no_difference "Trade.count" do
      convert({ security_id: securities(:aapl).id, qty: 2 }, transaction: depository_entry.transaction)
    end
    assert_response :unprocessable_entity
    assert_equal "not_investment_account", json["error"]
  end

  # Auth and permissions

  test "requires authentication" do
    get convert_to_trade_api_v1_transaction_url(@transaction)
    assert_response :unauthorized

    post convert_to_trade_api_v1_transaction_url(@transaction), params: { trade: { qty: 1 } }, as: :json
    assert_response :unauthorized
  end

  test "POST requires the read_write scope" do
    assert_no_difference "Trade.count" do
      convert({ security_id: securities(:aapl).id, qty: 2 }, key: @read_only_api_key)
    end
    assert_response :forbidden
    assert_equal "insufficient_scope", json["error"]
  end

  test "read-only and annotate shares cannot open or submit the conversion" do
    member = users(:family_member)
    member.api_keys.active.destroy_all
    key = create_key(member, [ "read_write" ])
    share = @account.account_shares.create!(user: member, permission: "read_only")

    %w[read_only read_write].each do |permission|
      share.update!(permission: permission)

      get convert_to_trade_api_v1_transaction_url(@transaction), headers: api_headers(key)
      assert_response :forbidden, permission

      assert_no_difference "Trade.count" do
        convert({ security_id: securities(:aapl).id, qty: 2 }, key: key)
      end
      assert_response :forbidden, permission
      assert_not @entry.reload.excluded?
    end

    share.update!(permission: "full_control")
    convert({ security_id: securities(:aapl).id, qty: 2 }, key: key)
    assert_response :created
  end

  test "another family's transaction returns 404" do
    other = users(:empty)
    other.api_keys.active.destroy_all
    key = create_key(other, [ "read_write" ])

    get convert_to_trade_api_v1_transaction_url(@transaction), headers: api_headers(key)
    assert_response :not_found

    assert_no_difference "Trade.count" do
      convert({ security_id: securities(:aapl).id, qty: 2 }, key: key)
    end
    assert_response :not_found
    assert_not @entry.reload.excluded?
  end
end
