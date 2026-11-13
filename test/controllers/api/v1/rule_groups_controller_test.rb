# frozen_string_literal: true

require "test_helper"

class Api::V1::RuleGroupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @user.api_keys.active.destroy_all

    @write_key = create_api_key(@user, "read_write")
    @read_key = create_api_key(@user, "read")

    @group = @family.rule_groups.create!(name: "Food")
    @rule = @family.rules.create!(name: "Coffee", resource_type: "transaction", rule_group: @group,
      actions: [ Rule::Action.new(action_type: "exclude_transaction") ])
  end

  teardown do
    ApiKey.where(user: [ @user, family_guest ]).find_each do |key|
      Redis.new.del("api_rate_limit:#{key.id}")
    end
  end

  test "index lists the family's groups in list order with their rule counts" do
    later = @family.rule_groups.create!(name: "Bills")
    other_family_group

    get api_v1_rule_groups_url, headers: json_headers(@read_key)

    assert_response :success
    groups = JSON.parse(response.body)["data"]
    assert_equal [ @group.id, later.id ], groups.map { |group| group["id"] }
    assert_equal "Food", groups.first["name"]
    assert_equal @group.position, groups.first["position"]
    assert_equal [ 1, 0 ], groups.map { |group| group["rules_count"] }
  end

  test "create adds a group at the end of the list" do
    assert_difference -> { @family.rule_groups.count }, 1 do
      post api_v1_rule_groups_url, params: { rule_group: { name: "  Bills " } }.to_json, headers: json_headers(@write_key)
    end

    assert_response :created
    group = JSON.parse(response.body)["data"]
    assert_equal "Bills", group["name"]
    assert_equal 0, group["rules_count"]
    assert_operator group["position"], :>, @rule.reload.position
  end

  test "create rejects a blank or taken name" do
    post api_v1_rule_groups_url, params: { rule_group: { name: "" } }.to_json, headers: json_headers(@write_key)
    assert_response :unprocessable_entity
    assert_equal "validation_failed", JSON.parse(response.body)["error"]

    post api_v1_rule_groups_url, params: { rule_group: { name: "Food" } }.to_json, headers: json_headers(@write_key)
    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"].first, "taken"
  end

  test "create requires a rule_group body" do
    post api_v1_rule_groups_url, params: {}.to_json, headers: json_headers(@write_key)

    assert_response :bad_request
  end

  test "update renames a group" do
    patch api_v1_rule_group_url(@group), params: { rule_group: { name: "Eating out" } }.to_json, headers: json_headers(@write_key)

    assert_response :success
    group = JSON.parse(response.body)["data"]
    assert_equal "Eating out", group["name"]
    assert_equal 1, group["rules_count"]
    assert_equal "Eating out", @group.reload.name
  end

  test "update rejects an invalid name" do
    patch api_v1_rule_group_url(@group), params: { rule_group: { name: "x" * 101 } }.to_json, headers: json_headers(@write_key)

    assert_response :unprocessable_entity
    assert_equal "Food", @group.reload.name
  end

  test "destroy deletes the group and keeps its rules, now without a group" do
    delete api_v1_rule_group_url(@group), headers: json_headers(@write_key)

    assert_response :no_content
    assert_not RuleGroup.exists?(@group.id)
    assert_nil @rule.reload.rule_group_id
  end

  test "another family's group is not found" do
    group = other_family_group

    patch api_v1_rule_group_url(group), params: { rule_group: { name: "Mine" } }.to_json, headers: json_headers(@write_key)
    assert_response :not_found

    delete api_v1_rule_group_url(group), headers: json_headers(@write_key)
    assert_response :not_found
    assert RuleGroup.exists?(group.id)
  end

  test "requires authentication" do
    get api_v1_rule_groups_url
    assert_response :unauthorized

    post api_v1_rule_groups_url, params: { rule_group: { name: "x" } }.to_json, headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized
  end

  test "writes reject a read-only key and a guest" do
    guest_key = create_api_key(family_guest, "read_write")

    [ @read_key, guest_key ].each do |key|
      post api_v1_rule_groups_url, params: { rule_group: { name: "New" } }.to_json, headers: json_headers(key)
      assert_response :forbidden

      patch api_v1_rule_group_url(@group), params: { rule_group: { name: "Renamed" } }.to_json, headers: json_headers(key)
      assert_response :forbidden

      delete api_v1_rule_group_url(@group), headers: json_headers(key)
      assert_response :forbidden
    end

    assert_equal "Food", @group.reload.name
    assert_not @family.rule_groups.exists?(name: "New")
  end

  test "a guest can list groups" do
    get api_v1_rule_groups_url, headers: json_headers(create_api_key(family_guest, "read"))

    assert_response :success
  end

  private
    def other_family_group
      Family.create!(name: "Other Family", currency: "USD", locale: "en").rule_groups.create!(name: "Theirs")
    end

    def create_api_key(user, scope)
      ApiKey.create!(
        user: user,
        name: "Rule groups #{scope} #{SecureRandom.hex(4)}",
        scopes: [ scope ],
        source: scope == "read" ? "mobile" : "web",
        display_key: "test_#{scope}_#{SecureRandom.hex(8)}"
      )
    end

    def json_headers(api_key)
      { "X-Api-Key" => api_key.plain_key, "Content-Type" => "application/json" }
    end
end
