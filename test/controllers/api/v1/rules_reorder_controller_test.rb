# frozen_string_literal: true

require "test_helper"

class Api::V1::RulesReorderControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @user.api_keys.active.destroy_all

    @write_key = create_api_key(@user, "read_write")
    @read_key = create_api_key(@user, "read")

    @group = @family.rule_groups.create!(name: "Food")
    @first = create_rule("First")
    @grouped = create_rule("Grouped", group: @group)
    @last = create_rule("Last")
  end

  teardown do
    ApiKey.where(user: [ @user, family_guest ]).find_each do |key|
      Redis.new.del("api_rate_limit:#{key.id}")
    end
  end

  test "index lists rules in run order, not creation order" do
    @family.rules.where(id: @last.id).update_all(position: 0)

    get api_v1_rules_url, headers: json_headers(@read_key)

    assert_response :success
    assert_equal @family.rules.ordered.pluck(:id), JSON.parse(response.body)["data"].map { |rule| rule["id"] }
    assert_equal @last.id, JSON.parse(response.body)["data"].first["id"]
  end

  test "rule json carries position and its group" do
    get api_v1_rule_url(@grouped), headers: json_headers(@read_key)

    rule = JSON.parse(response.body)["data"]
    assert_equal @grouped.reload.position, rule["position"]
    assert_equal @group.id, rule["rule_group_id"]
    assert_equal({ "id" => @group.id, "name" => "Food" }, rule["rule_group"])

    get api_v1_rule_url(@first), headers: json_headers(@read_key)
    assert_nil JSON.parse(response.body)["data"]["rule_group"]
  end

  test "reorder sets the family's order and returns the rules in it" do
    new_order = [ @last.id, @grouped.id, *other_rule_ids, @first.id ]

    patch reorder_api_v1_rules_url, params: { rule_ids: new_order }.to_json, headers: json_headers(@write_key)

    assert_response :success
    rules = JSON.parse(response.body)["rules"]
    assert_equal new_order, rules.map { |rule| rule["id"] }
    assert_equal rules.map { |rule| rule["position"] }.sort, rules.map { |rule| rule["position"] }
    assert_equal new_order, @family.rules.ordered.pluck(:id)
  end

  test "reorder rejects ids that are not exactly the family's rules" do
    before = @family.rules.ordered.pluck(:id)

    [
      [ @first.id, @grouped.id ],
      [ *before, before.first ],
      [ *before.drop(1), other_family_rule.id ],
      [ *before, SecureRandom.uuid ]
    ].each do |rule_ids|
      patch reorder_api_v1_rules_url, params: { rule_ids: rule_ids }.to_json, headers: json_headers(@write_key)

      assert_response :unprocessable_entity
      assert_equal "validation_failed", JSON.parse(response.body)["error"]
    end

    assert_equal before, @family.rules.ordered.pluck(:id)
  end

  test "reorder rejects a list that splits a group" do
    second_grouped = create_rule("Grouped two", group: @group)
    rule_ids = [ @grouped.id, @first.id, second_grouped.id, @last.id, *(other_rule_ids - [ second_grouped.id ]) ]

    patch reorder_api_v1_rules_url, params: { rule_ids: rule_ids }.to_json, headers: json_headers(@write_key)

    assert_response :unprocessable_entity
    assert_match "same group", JSON.parse(response.body)["message"]
  end

  test "reorder requires rule_ids" do
    patch reorder_api_v1_rules_url, params: {}.to_json, headers: json_headers(@write_key)

    assert_response :bad_request
  end

  test "reorder requires authentication, a write key and a non-guest" do
    rule_ids = @family.rules.ordered.pluck(:id).reverse

    patch reorder_api_v1_rules_url, params: { rule_ids: rule_ids }.to_json, headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized

    patch reorder_api_v1_rules_url, params: { rule_ids: rule_ids }.to_json, headers: json_headers(@read_key)
    assert_response :forbidden

    patch reorder_api_v1_rules_url, params: { rule_ids: rule_ids }.to_json,
      headers: json_headers(create_api_key(family_guest, "read_write"))
    assert_response :forbidden

    assert_not_equal rule_ids, @family.rules.ordered.pluck(:id)
  end

  private
    def other_rule_ids
      @family.rules.where.not(id: [ @first.id, @grouped.id, @last.id ]).ordered.pluck(:id)
    end

    def create_rule(name, group: nil)
      @family.rules.create!(name: name, resource_type: "transaction", rule_group: group,
        actions: [ Rule::Action.new(action_type: "exclude_transaction") ])
    end

    def create_api_key(user, scope)
      ApiKey.create!(
        user: user,
        name: "Rules #{scope} #{SecureRandom.hex(4)}",
        scopes: [ scope ],
        source: scope == "read" ? "mobile" : "web",
        display_key: "test_#{scope}_#{SecureRandom.hex(8)}"
      )
    end

    def json_headers(api_key)
      { "X-Api-Key" => api_key.plain_key, "Content-Type" => "application/json" }
    end

    def other_family_rule
      other_family = Family.create!(name: "Other Family", currency: "USD", locale: "en")
      other_family.rules.create!(name: "Other", resource_type: "transaction",
        actions: [ Rule::Action.new(action_type: "exclude_transaction") ])
    end
end
