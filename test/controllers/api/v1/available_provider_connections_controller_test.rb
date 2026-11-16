# frozen_string_literal: true

require "test_helper"

class Api::V1::AvailableProviderConnectionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:family_admin)
    @member = users(:family_member)
    ApiKey.where(user: [ @admin, @member ]).destroy_all
    @admin_key = create_api_key(@admin, "read")
    @member_key = create_api_key(@member, "read")
  end

  teardown do
    ApiKey.where(user: [ @admin, @member, family_guest ]).find_each { |key| Redis.new.del("api_rate_limit:#{key.id}") }
  end

  test "admins get every provider panel, typed by how the app connects it" do
    Family.any_instance.stubs(:can_connect_plaid_us?).returns(false)
    Family.any_instance.stubs(:can_connect_plaid_eu?).returns(false)

    get api_v1_available_provider_connections_url, headers: api_headers(@admin_key)

    assert_response :success
    entries = JSON.parse(response.body)["data"]
    by_provider = entries.index_by { |entry| entry["provider"] }

    assert_equal Settings::ProvidersController::FAMILY_PANEL_KEYS.sort, by_provider.keys.sort
    assert_equal entries.map { |entry| entry["name"].downcase }.sort, entries.map { |entry| entry["name"].downcase }
    assert_equal({ "provider" => "simplefin", "key" => "simplefin", "name" => "SimpleFIN",
                   "connect_path" => "/settings/providers/simplefin/connect_form", "kind" => "token" }, by_provider["simplefin"])
    assert_equal "web", by_provider["enable_banking"]["kind"]
    assert_equal "web", by_provider["snaptrade"]["kind"]
    assert_equal ProviderConnectionSetup::SETUP_CLASSES.keys.sort,
      entries.select { |entry| entry["kind"] == "token" }.map { |entry| entry["provider"] }.sort
    entries.each do |entry|
      assert WebHandoff::RoutePolicy.entry_path_allowed?(entry["connect_path"]), entry["connect_path"]
    end
  end

  test "Plaid is listed only when the instance has Plaid credentials" do
    Family.any_instance.stubs(:can_connect_plaid_us?).returns(true)
    Family.any_instance.stubs(:can_connect_plaid_eu?).returns(false)

    get api_v1_available_provider_connections_url, headers: api_headers(@admin_key)

    plaid = JSON.parse(response.body)["data"].select { |entry| entry["provider"] == "plaid" }
    assert_equal [ { "provider" => "plaid", "key" => "plaid_us", "name" => "Plaid",
                     "connect_path" => "/plaid_items/new?region=us", "kind" => "web" } ], plaid
    assert WebHandoff::RoutePolicy.entry_path_allowed?(plaid.first["connect_path"])

    Family.any_instance.stubs(:can_connect_plaid_us?).returns(false)
    get api_v1_available_provider_connections_url, headers: api_headers(@admin_key)
    assert_empty JSON.parse(response.body)["data"].select { |entry| entry["provider"] == "plaid" }
  end

  test "members get only the providers a member may connect on the web" do
    Family.any_instance.stubs(:can_connect_plaid_us?).returns(true)
    Family.any_instance.stubs(:can_connect_plaid_eu?).returns(false)

    get api_v1_available_provider_connections_url, headers: api_headers(@member_key)

    assert_response :success
    assert_equal [ "plaid_us" ], JSON.parse(response.body)["data"].map { |entry| entry["key"] }
  end

  test "guests get nothing" do
    get api_v1_available_provider_connections_url, headers: api_headers(create_api_key(family_guest, "read"))

    assert_response :success
    assert_equal [], JSON.parse(response.body)["data"]
  end

  test "requires authentication" do
    get api_v1_available_provider_connections_url

    assert_response :unauthorized
  end

  test "requires the read scope" do
    write_only_key = ApiKey.new(user: @admin, name: "Write only", scopes: [ "write" ],
      display_key: "test_write_#{SecureRandom.hex(8)}", source: "monitoring").tap { |key| key.save!(validate: false) }

    get api_v1_available_provider_connections_url, headers: api_headers(write_only_key)

    assert_response :forbidden
  end

  test "connection rows carry the web's reconnect page only when they need attention" do
    plaid_item = plaid_items(:one)
    plaid_item.update!(status: :requires_update)
    simplefin_item = SimplefinItem.create!(family: @admin.family, name: "Needs token", access_url: "https://example.com/a",
      status: :requires_update)
    healthy_item = SimplefinItem.create!(family: @admin.family, name: "Healthy", access_url: "https://example.com/b")
    mercury_item = mercury_items(:one)
    mercury_item.update!(status: :requires_update)

    get api_v1_provider_connections_url, headers: api_headers(@admin_key)

    assert_response :success
    # Fixtures named "one" share an id across provider tables.
    rows = JSON.parse(response.body)["data"].index_by { |row| [ row["provider"], row["id"] ] }
    assert_equal "/plaid_items/#{plaid_item.id}/edit", rows[[ "plaid", plaid_item.id ]]["reconnect_path"]
    assert_equal "/simplefin_items/#{simplefin_item.id}/edit", rows[[ "simplefin", simplefin_item.id ]]["reconnect_path"]
    assert_equal "/settings/providers/mercury/connect_form", rows[[ "mercury", mercury_item.id ]]["reconnect_path"]
    assert rows.key?([ "simplefin", healthy_item.id ])
    assert_nil rows[[ "simplefin", healthy_item.id ]]["reconnect_path"]
    [ [ "plaid", plaid_item ], [ "simplefin", simplefin_item ], [ "mercury", mercury_item ] ].each do |provider, item|
      assert WebHandoff::RoutePolicy.entry_path_allowed?(rows[[ provider, item.id ]]["reconnect_path"])
    end
  end

  test "a member only gets reconnect pages they could open on the web" do
    plaid_item = plaid_items(:one)
    plaid_item.update!(status: :requires_update)
    owned_plaid = PlaidItem.create!(family: @member.family, owner: @member, plaid_id: "item_member_1",
      access_token: "token_member_1", name: "Member Bank", status: :requires_update)
    simplefin_item = SimplefinItem.create!(family: @member.family, name: "Needs token", access_url: "https://example.com/a",
      status: :requires_update)

    get api_v1_provider_connections_url, headers: api_headers(@member_key)

    # Fixtures named "one" share an id across provider tables.
    rows = JSON.parse(response.body)["data"].index_by { |row| [ row["provider"], row["id"] ] }
    assert_equal "/plaid_items/#{owned_plaid.id}/edit", rows[[ "plaid", owned_plaid.id ]]["reconnect_path"]
    assert_nil rows[[ "plaid", plaid_item.id ]]["reconnect_path"]
    assert_nil rows[[ "simplefin", simplefin_item.id ]]["reconnect_path"]
  end

  private
    def create_api_key(user, scope)
      ApiKey.create!(user: user, name: "Available #{scope} #{SecureRandom.hex(4)}", scopes: [ scope ], source: "web",
        display_key: "test_available_#{scope}_#{SecureRandom.hex(8)}")
    end
end
