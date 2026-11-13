# frozen_string_literal: true

require "test_helper"

class Api::V1::RulesApplyAllControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper
  include ActiveJob::TestHelper

  setup do
    @user = users(:family_admin)
    @family = @user.family
    @user.api_keys.active.destroy_all

    @write_key = create_api_key(@user, "read_write")
    @read_key = create_api_key(@user, "read")

    @family.rules.destroy_all
    @coffee = create_rule("coffee zq", "Coffee")
    @tea = create_rule("tea zq", "Tea")
  end

  teardown do
    ApiKey.where(user: [ @user, family_guest ]).find_each do |key|
      Redis.new.del("api_rate_limit:#{key.id}")
    end
  end

  test "apply_all asks for confirmation and says what the web dialog says" do
    create_transaction(name: "Coffee zq tea zq", amount: 10)
    create_transaction(name: "Tea zq shop", amount: 10)

    assert_no_enqueued_jobs only: ApplyAllRulesJob do
      post apply_all_api_v1_rules_url, headers: json_headers(@write_key)
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "confirmation_required", body["error"]
    assert_equal({
      "rule_count" => 2,
      "affected_resource_count" => 2,
      "auto_categorize" => false,
      "ai_model" => nil,
      "estimated_ai_cost" => nil
    }, body["confirmation"])
  end

  test "apply_all confirmation names the AI model and cost when a rule auto-categorizes" do
    @tea.actions.destroy_all
    @tea.actions.create!(action_type: "auto_categorize")
    create_transaction(name: "Tea zq shop", amount: 10)
    Family.any_instance.stubs(:categorization_model_name).returns("gpt-4.1")

    post apply_all_api_v1_rules_url, params: { confirm: false }.to_json, headers: json_headers(@write_key)

    assert_response :unprocessable_entity
    confirmation = JSON.parse(response.body)["confirmation"]
    assert_equal true, confirmation["auto_categorize"]
    assert_equal "gpt-4.1", confirmation["ai_model"]
    expected_cost = LlmUsage.estimate_auto_categorize_cost(
      transaction_count: 1, category_count: @family.categories.count, model: "gpt-4.1"
    )
    assert_equal expected_cost, confirmation["estimated_ai_cost"]
  end

  test "apply_all with confirm queues every rule like the web" do
    assert_enqueued_with(job: ApplyAllRulesJob, args: [ @family ]) do
      post apply_all_api_v1_rules_url, params: { confirm: true }.to_json, headers: json_headers(@write_key)
    end

    assert_response :accepted
    assert_equal({ "status" => "queued", "rule_count" => 2 }, JSON.parse(response.body)["data"])
  end

  test "the queued job runs every rule, inactive ones too" do
    entry = create_transaction(name: "Coffee zq shop", amount: 10)

    perform_enqueued_jobs only: ApplyAllRulesJob do
      post apply_all_api_v1_rules_url, params: { confirm: true }.to_json, headers: json_headers(@write_key)
    end

    assert_equal "Coffee", entry.reload.name
    assert_equal 2, RuleRun.where(rule: [ @coffee, @tea ], execution_type: "manual").count
  end

  test "apply_all reports a job that could not be queued" do
    ApplyAllRulesJob.stubs(:perform_later).returns(false)

    post apply_all_api_v1_rules_url, params: { confirm: true }.to_json, headers: json_headers(@write_key)

    assert_response :service_unavailable
    assert_equal "enqueue_failed", JSON.parse(response.body)["error"]
  end

  test "apply_all requires authentication, a write key and a non-guest" do
    assert_no_enqueued_jobs only: ApplyAllRulesJob do
      post apply_all_api_v1_rules_url, params: { confirm: true }.to_json, headers: { "Content-Type" => "application/json" }
      assert_response :unauthorized

      post apply_all_api_v1_rules_url, params: { confirm: true }.to_json, headers: json_headers(@read_key)
      assert_response :forbidden

      post apply_all_api_v1_rules_url, params: { confirm: true }.to_json,
        headers: json_headers(create_api_key(family_guest, "read_write"))
      assert_response :forbidden
    end
  end

  private
    def create_rule(match, new_name)
      rule = @family.rules.build(name: new_name, resource_type: "transaction", active: false)
      rule.conditions.build(condition_type: "transaction_name", operator: "like", value: match)
      rule.actions.build(action_type: "set_transaction_name", value: new_name)
      rule.save!
      rule
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
end
