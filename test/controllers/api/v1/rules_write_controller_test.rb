# frozen_string_literal: true

require "test_helper"

class Api::V1::RulesWriteControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    @user = users(:family_admin)
    @family = @user.family
    @user.api_keys.active.destroy_all

    @write_key = create_api_key(@user, "read_write")
    @read_key = create_api_key(@user, "read")

    @rule = @family.rules.build(name: "Coffee cleanup", resource_type: "transaction", active: false)
    @rule.conditions.build(condition_type: "transaction_name", operator: "like", value: "coffee zq")
    @rule.conditions.build(
      condition_type: "compound",
      operator: "or",
      sub_conditions: [
        Rule::Condition.new(condition_type: "transaction_amount", operator: ">", value: "1"),
        Rule::Condition.new(condition_type: "transaction_amount", operator: "<", value: "500")
      ]
    )
    @rule.actions.build(action_type: "set_transaction_name", value: "Coffee")
    @rule.save!
  end

  teardown do
    ApiKey.where(user: [ @user, users(:family_member) ]).find_each do |key|
      Redis.new.del("api_rate_limit:#{key.id}")
    end
  end

  test "create builds a rule with nested and compound conditions" do
    assert_difference -> { @family.rules.count }, 1 do
      post api_v1_rules_url, params: {
        rule: {
          name: "Groceries",
          effective_date: "2024-02-01",
          stop_processing: true,
          conditions: [
            { condition_type: "transaction_name", operator: "like", value: "market" },
            {
              condition_type: "compound",
              operator: "and",
              sub_conditions: [
                { condition_type: "transaction_amount", operator: ">", value: "20" },
                { condition_type: "transaction_amount", operator: "<", value: "40" }
              ]
            }
          ],
          actions: [
            { action_type: "set_transaction_category", value: categories(:food_and_drink).id }
          ]
        }
      }.to_json, headers: json_headers(@write_key)
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal [], body["warnings"]

    rule = body["data"]
    assert_equal "Groceries", rule["name"]
    assert_equal "transaction", rule["resource_type"]
    assert_equal false, rule["active"]
    assert_equal "2024-02-01", rule["effective_date"]
    assert_equal true, rule["stop_processing"]
    assert_equal 2, rule["conditions"].length
    compound = rule["conditions"].find { |condition| condition["condition_type"] == "compound" }
    assert_equal %w[20 40], compound["sub_conditions"].map { |sub| sub["value"] }
    assert_equal [ categories(:food_and_drink).id ], rule["actions"].map { |action| action["value"] }

    get api_v1_rule_url(rule["id"]), headers: json_headers(@read_key)
    assert_equal rule, JSON.parse(response.body)["data"]
  end

  test "create ignores ids copied from another rule" do
    get api_v1_rule_url(@rule), headers: json_headers(@read_key)
    copy = JSON.parse(response.body)["data"].merge("name" => "Copy")

    post api_v1_rules_url, params: { rule: copy }.to_json, headers: json_headers(@write_key)

    assert_response :created
    created = JSON.parse(response.body)["data"]
    assert_not_equal @rule.id, created["id"]
    assert_equal 2, created["conditions"].length
    assert_equal 2, @rule.reload.conditions.count
    assert_equal 2, @rule.conditions.find(&:compound?).sub_conditions.count
  end

  test "create rejects a rule without actions" do
    assert_no_difference -> { Rule.count } do
      post api_v1_rules_url, params: {
        rule: { conditions: [ { condition_type: "transaction_name", operator: "like", value: "x" } ], actions: [] }
      }.to_json, headers: json_headers(@write_key)
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "validation_failed", body["error"]
    assert body["errors"].any?
  end

  test "create rejects an unknown action type and nested compound conditions" do
    post api_v1_rules_url, params: {
      rule: {
        conditions: [
          { condition_type: "compound", operator: "and",
            sub_conditions: [ { condition_type: "compound", operator: "or" } ] }
        ],
        actions: [ { action_type: "launch_rockets", value: "1" } ]
      }
    }.to_json, headers: json_headers(@write_key)

    assert_response :unprocessable_entity
    assert_equal "validation_failed", JSON.parse(response.body)["error"]
  end

  test "create puts the rule in a new group" do
    post api_v1_rules_url, params: {
      rule: {
        new_rule_group_name: "Food",
        conditions: [ { condition_type: "transaction_name", operator: "like", value: "pizza" } ],
        actions: [ { action_type: "set_transaction_name", value: "Pizza" } ]
      }
    }.to_json, headers: json_headers(@write_key)

    assert_response :created
    group = @family.rule_groups.find_by!(name: "Food")
    assert_equal group.id, JSON.parse(response.body)["data"]["rule_group_id"]
  end

  test "create rejects another family's rule group" do
    other_family = Family.create!(name: "Other", currency: "USD", locale: "en")
    other_group = other_family.rule_groups.create!(name: "Theirs")

    post api_v1_rules_url, params: {
      rule: {
        rule_group_id: other_group.id,
        conditions: [ { condition_type: "transaction_name", operator: "like", value: "pizza" } ],
        actions: [ { action_type: "set_transaction_name", value: "Pizza" } ]
      }
    }.to_json, headers: json_headers(@write_key)

    assert_response :unprocessable_entity
  end

  test "member can create a rule" do
    member_key = create_api_key(users(:family_member), "read_write")

    post api_v1_rules_url, params: {
      rule: {
        conditions: [ { condition_type: "transaction_name", operator: "like", value: "tea" } ],
        actions: [ { action_type: "set_transaction_name", value: "Tea" } ]
      }
    }.to_json, headers: json_headers(member_key)

    assert_response :created
  end

  test "writes require authentication" do
    post api_v1_rules_url, params: { rule: { name: "x" } }.to_json, headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized

    patch api_v1_rule_url(@rule), params: { rule: { name: "x" } }.to_json, headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized

    delete api_v1_rule_url(@rule)
    assert_response :unauthorized

    post apply_api_v1_rule_url(@rule)
    assert_response :unauthorized
  end

  test "writes reject a read-only key" do
    post api_v1_rules_url, params: { rule: { name: "x" } }.to_json, headers: json_headers(@read_key)
    assert_response :forbidden
    assert_equal "insufficient_scope", JSON.parse(response.body)["error"]

    patch api_v1_rule_url(@rule), params: { rule: { name: "x" } }.to_json, headers: json_headers(@read_key)
    assert_response :forbidden

    delete api_v1_rule_url(@rule), headers: json_headers(@read_key)
    assert_response :forbidden

    post apply_api_v1_rule_url(@rule), params: { confirm: true }.to_json, headers: json_headers(@read_key)
    assert_response :forbidden

    assert_equal "Coffee cleanup", @rule.reload.name
    assert_not @rule.active?
  end

  test "guests cannot write rules" do
    guest_key = create_api_key(family_guest, "read_write")

    assert_no_difference -> { Rule.count } do
      post api_v1_rules_url, params: {
        rule: { actions: [ { action_type: "set_transaction_name", value: "x" } ] }
      }.to_json, headers: json_headers(guest_key)
    end
    assert_response :forbidden

    patch api_v1_rule_url(@rule), params: { rule: { name: "Guest" } }.to_json, headers: json_headers(guest_key)
    assert_response :forbidden

    delete api_v1_rule_url(@rule), headers: json_headers(guest_key)
    assert_response :forbidden

    post apply_api_v1_rule_url(@rule), params: { confirm: true }.to_json, headers: json_headers(guest_key)
    assert_response :forbidden

    assert_equal "Coffee cleanup", @rule.reload.name
    assert_not @rule.active?
  end

  test "update takes back the GET shape and replaces the lists it is sent" do
    get api_v1_rule_url(@rule), headers: json_headers(@read_key)
    rule = JSON.parse(response.body)["data"]

    name_condition = rule["conditions"].find { |condition| condition["condition_type"] == "transaction_name" }
    compound = rule["conditions"].find { |condition| condition["condition_type"] == "compound" }
    name_condition["value"] = "latte zq"
    compound["sub_conditions"].pop
    rule["name"] = "Latte cleanup"
    rule["actions"] << { "action_type" => "set_transaction_tags", "value" => [ tags(:one).id ] }

    patch api_v1_rule_url(@rule), params: { rule: rule }.to_json, headers: json_headers(@write_key)

    assert_response :success
    updated = JSON.parse(response.body)["data"]
    assert_equal "Latte cleanup", updated["name"]
    assert_equal name_condition["id"], updated["conditions"].find { |c| c["condition_type"] == "transaction_name" }["id"]
    assert_equal "latte zq", @rule.conditions.find(name_condition["id"]).value
    assert_equal 1, @rule.conditions.find(compound["id"]).sub_conditions.count
    assert_equal %w[set_transaction_name set_transaction_tags], @rule.reload.actions.map(&:action_type).sort
  end

  test "update removes saved conditions left out of the list" do
    patch api_v1_rule_url(@rule), params: {
      rule: { conditions: [ { condition_type: "transaction_name", operator: "like", value: "new zq" } ] }
    }.to_json, headers: json_headers(@write_key)

    assert_response :success
    assert_equal [ "new zq" ], @rule.reload.conditions.map(&:value)
    assert_equal 0, Rule::Condition.where(parent_id: nil, rule_id: nil).count
  end

  test "update leaves conditions and actions alone when they are not sent" do
    patch api_v1_rule_url(@rule), params: { rule: { name: "Renamed" } }.to_json, headers: json_headers(@write_key)

    assert_response :success
    @rule.reload
    assert_equal "Renamed", @rule.name
    assert_equal 2, @rule.conditions.count
    assert_equal 1, @rule.actions.count
  end

  test "update rejects removing every action" do
    patch api_v1_rule_url(@rule), params: { rule: { actions: [] } }.to_json, headers: json_headers(@write_key)

    assert_response :unprocessable_entity
    assert_equal "validation_failed", JSON.parse(response.body)["error"]
    assert_equal 1, @rule.reload.actions.count
  end

  test "update rejects a condition id from another rule" do
    other = @family.rules.build(resource_type: "transaction")
    other.conditions.build(condition_type: "transaction_name", operator: "like", value: "other")
    other.actions.build(action_type: "set_transaction_name", value: "Other")
    other.save!

    patch api_v1_rule_url(@rule), params: {
      rule: { conditions: [ { id: other.conditions.first.id, condition_type: "transaction_name", operator: "like", value: "stolen" } ] }
    }.to_json, headers: json_headers(@write_key)

    assert_response :unprocessable_entity
    assert_equal "validation_failed", JSON.parse(response.body)["error"]
    assert_equal "other", other.conditions.first.reload.value
  end

  test "update and delete do not reach another family's rule" do
    other_rule = other_family_rule

    patch api_v1_rule_url(other_rule), params: { rule: { name: "Mine" } }.to_json, headers: json_headers(@write_key)
    assert_response :not_found
    assert_equal "record_not_found", JSON.parse(response.body)["error"]

    delete api_v1_rule_url(other_rule), headers: json_headers(@write_key)
    assert_response :not_found

    post apply_api_v1_rule_url(other_rule), params: { confirm: true }.to_json, headers: json_headers(@write_key)
    assert_response :not_found

    assert Rule.exists?(other_rule.id)
  end

  test "destroy deletes the rule with its conditions and actions" do
    condition_ids = @rule.conditions.map(&:id) + @rule.conditions.flat_map { |c| c.sub_conditions.map(&:id) }

    delete api_v1_rule_url(@rule), headers: json_headers(@write_key)

    assert_response :no_content
    assert_not Rule.exists?(@rule.id)
    assert_equal 0, Rule::Condition.where(id: condition_ids).count
  end

  test "apply asks for confirmation and says what the web dialog says" do
    create_transaction(name: "Coffee zq shop", amount: 10)

    post apply_api_v1_rule_url(@rule), headers: json_headers(@write_key)

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "confirmation_required", body["error"]
    assert_equal 1, body["confirmation"]["affected_resource_count"]
    assert_equal 0, body["confirmation"]["active_rules_above_count"]
    assert_equal false, body["confirmation"]["auto_categorize"]
    assert_nil body["confirmation"]["estimated_ai_cost"]
    assert_not @rule.reload.active?
    assert_equal 0, @rule.rule_runs.count
  end

  test "apply confirmation names the AI model and cost for auto-categorize" do
    @rule.actions.destroy_all
    @rule.actions.create!(action_type: "auto_categorize")
    create_transaction(name: "Coffee zq shop", amount: 10)
    Family.any_instance.stubs(:categorization_model_name).returns("gpt-4.1")

    post apply_api_v1_rule_url(@rule), params: { confirm: false }.to_json, headers: json_headers(@write_key)

    assert_response :unprocessable_entity
    confirmation = JSON.parse(response.body)["confirmation"]
    assert_equal true, confirmation["auto_categorize"]
    assert_equal "gpt-4.1", confirmation["ai_model"]
    expected_cost = LlmUsage.estimate_auto_categorize_cost(
      transaction_count: 1, category_count: @family.categories.count, model: "gpt-4.1"
    )
    assert_equal expected_cost, confirmation["estimated_ai_cost"]
  end

  test "apply with confirm switches the rule on, runs it and returns the run" do
    entry = create_transaction(name: "Coffee zq shop", amount: 10)

    post apply_api_v1_rule_url(@rule), params: { confirm: true }.to_json, headers: json_headers(@write_key)

    assert_response :created
    run = JSON.parse(response.body)["data"]
    assert_equal @rule.id, run["rule_id"]
    assert_equal "manual", run["execution_type"]
    assert_equal "success", run["status"]
    assert_equal 1, run["transactions_queued"]
    assert_equal 1, run["transactions_modified"]
    assert_equal true, run["rule"]["active"]

    assert @rule.reload.active?
    assert_equal "Coffee", entry.reload.name
  end

  test "apply reports a run already in progress" do
    Rule::Runner.any_instance.stubs(:run).raises(Rule::Runner::LockBusy)

    post apply_api_v1_rule_url(@rule), params: { confirm: true }.to_json, headers: json_headers(@write_key)

    assert_response :conflict
    assert_equal "rules_running", JSON.parse(response.body)["error"]
  end

  test "apply leaves an email rule off and runs nothing when its baseline times out" do
    account = @family.accounts.create!(name: "Baseline", balance: 1000, currency: "USD", accountable: Depository.new)
    rule = Rule.create!(
      family: @family, resource_type: "transaction", active: false,
      conditions: [ Rule::Condition.new(condition_type: "transaction_name", operator: "matches_regex", value: "baseline match zq") ],
      actions: [ Rule::Action.new(action_type: "send_email_notification") ]
    )
    create_transaction(date: Date.current, account: account, name: "Baseline match zq")
    Rule::SafeRegex.stubs(:with_timeout).raises(Rule::SafeRegex::TimeoutError)

    post apply_api_v1_rule_url(rule), params: { confirm: true }.to_json, headers: json_headers(@write_key)

    assert_response :unprocessable_entity
    assert_equal "notification_baseline_timed_out", JSON.parse(response.body)["error"]
    assert_not rule.reload.active?
    assert_equal 0, rule.rule_runs.count
  end

  private

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
      rule = other_family.rules.build(name: "Other", resource_type: "transaction")
      rule.conditions.build(condition_type: "transaction_name", operator: "like", value: "other")
      rule.actions.build(action_type: "set_transaction_name", value: "Other")
      rule.save!
      rule
    end
end
