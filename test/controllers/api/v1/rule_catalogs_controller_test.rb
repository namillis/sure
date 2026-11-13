# frozen_string_literal: true

require "test_helper"

class Api::V1::RuleCatalogsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @family = @user.family

    @user.api_keys.active.destroy_all
    @api_key = ApiKey.create!(
      user: @user,
      name: "Test Read Key",
      scopes: [ "read" ],
      source: "web",
      display_key: "test_read_#{SecureRandom.hex(8)}"
    )

    Redis.new.del("api_rate_limit:#{@api_key.id}")
  end

  test "lists every condition filter and action executor in the registry" do
    Provider::Registry.stubs(:preferred_llm_provider).returns(nil)

    get catalog_api_v1_rules_url(resource_type: "transaction"), headers: api_headers(@api_key)

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "transaction", json["resource_type"]
    assert_equal Rule::Registry::TransactionResource.condition_filter_keys, json["conditions"].map { |condition| condition["key"] }
    assert_equal Rule::Registry::TransactionResource.action_executor_keys, json["actions"].map { |action| action["key"] }
  end

  test "defaults to the transaction resource type" do
    get catalog_api_v1_rules_url, headers: api_headers(@api_key)

    assert_response :success
    assert_equal "transaction", JSON.parse(response.body)["resource_type"]
  end

  test "describes conditions the way the rule form renders them" do
    get catalog_api_v1_rules_url, headers: api_headers(@api_key)

    conditions = JSON.parse(response.body)["conditions"].index_by { |condition| condition["key"] }

    name = conditions.fetch("transaction_name")
    assert_equal "text", name["type"]
    assert_nil name["options"]
    assert_nil name["number_step"]
    assert_includes name["operators"], { "key" => "like", "label" => "Contains", "requires_value" => true }
    assert_includes name["operators"], { "key" => "is_null", "label" => "Is empty", "requires_value" => false }

    assert_equal "number", conditions.fetch("transaction_amount")["type"]
    assert_not_nil conditions.fetch("transaction_amount")["number_step"]

    type = conditions.fetch("transaction_type")
    assert_equal [ { "key" => "=", "label" => "Equal to", "requires_value" => true } ], type["operators"]
    assert_equal %w[income expense transfer], type["options"].map { |option| option["value"] }

    tag_ids = conditions.fetch("transaction_tag")["options"].map { |option| option["value"] }
    assert_equal @family.tags.alphabetically.pluck(:id), tag_ids

    account_ids = conditions.fetch("transaction_account")["options"].map { |option| option["value"] }
    assert_equal @family.accounts.accessible_by(@user).alphabetically.pluck(:name, :id).map(&:last), account_ids
  end

  test "describes actions with their value type" do
    get catalog_api_v1_rules_url, headers: api_headers(@api_key)

    actions = JSON.parse(response.body)["actions"].index_by { |action| action["key"] }

    assert_equal "select", actions.fetch("set_transaction_category")["value_type"]
    assert_equal "multi_select", actions.fetch("set_transaction_tags")["value_type"]
    assert_equal "text", actions.fetch("set_transaction_name")["value_type"]
    assert_nil actions.fetch("set_transaction_name")["options"]
    assert_equal "function", actions.fetch("exclude_transaction")["value_type"]
    assert_equal "split", actions.fetch("split_transaction")["value_type"]
    assert_nil actions.fetch("split_transaction")["options"]
    assert_equal false, actions.fetch("set_transaction_name")["requires_ai"]
    assert_equal true, actions.fetch("set_transaction_name")["available"]
  end

  test "marks AI actions unavailable without a provider" do
    Provider::Registry.stubs(:preferred_llm_provider).returns(nil)

    get catalog_api_v1_rules_url, headers: api_headers(@api_key)

    json = JSON.parse(response.body)
    actions = json["actions"].index_by { |action| action["key"] }
    assert_equal false, json["ai_available"]
    %w[auto_categorize auto_detect_merchants].each do |key|
      assert_equal true, actions.fetch(key)["requires_ai"]
      assert_equal false, actions.fetch(key)["available"]
    end
  end

  test "marks AI actions available with a provider" do
    Provider::Registry.stubs(:preferred_llm_provider).returns(mock("llm_provider"))

    get catalog_api_v1_rules_url, headers: api_headers(@api_key)

    json = JSON.parse(response.body)
    actions = json["actions"].index_by { |action| action["key"] }
    assert_equal true, json["ai_available"]
    assert_equal true, actions.fetch("auto_categorize")["available"]
    assert_equal true, actions.fetch("auto_detect_merchants")["available"]
  end

  test "labels follow the user's locale" do
    @user.update!(locale: "fr")

    get catalog_api_v1_rules_url, headers: api_headers(@api_key)

    name = JSON.parse(response.body)["conditions"].find { |condition| condition["key"] == "transaction_name" }
    assert_includes name["operators"].map { |operator| operator["label"] }, "Contient"
  end

  test "only lists another family's options when asked by that family" do
    other_family = Family.create!(name: "Other Family", currency: "USD", locale: "en")
    other_tag = other_family.tags.create!(name: "Other family tag")

    get catalog_api_v1_rules_url, headers: api_headers(@api_key)

    tag_ids = JSON.parse(response.body)["conditions"].find { |condition| condition["key"] == "transaction_tag" }["options"].map { |option| option["value"] }
    assert_not_includes tag_ids, other_tag.id
  end

  test "rejects an unknown resource type" do
    get catalog_api_v1_rules_url(resource_type: "account"), headers: api_headers(@api_key)

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal "validation_failed", json["error"]
    assert_equal [ "resource_type must be one of: transaction" ], json["errors"]
  end

  test "allows a read write key" do
    read_write_key = ApiKey.create!(
      user: users(:family_member),
      name: "Test Read Write Key",
      scopes: [ "read_write" ],
      source: "web",
      display_key: "test_rw_#{SecureRandom.hex(8)}"
    )

    get catalog_api_v1_rules_url, headers: api_headers(read_write_key)

    assert_response :success
  end

  test "requires authentication" do
    get catalog_api_v1_rules_url

    assert_response :unauthorized
  end

  test "requires the read scope" do
    key = ApiKey.generate_secure_key
    no_scope_key = ApiKey.new(user: @user, name: "No scope", key: key, scopes: [], display_key: key, source: "mobile")
    no_scope_key.save!(validate: false)

    get catalog_api_v1_rules_url, headers: { "X-Api-Key" => key }

    assert_response :forbidden
  end
end
