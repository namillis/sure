# frozen_string_literal: true

require "test_helper"

class Api::V1::AiSettingsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admin = users(:family_admin)
    @member = users(:family_member)
    @family = @admin.family
    @other_family = families(:empty)
    [ @admin, @member ].each { |user| user.api_keys.active.destroy_all }

    @read_key = create_api_key(@admin, "read")
    @write_key = create_api_key(@admin, "read_write")
    @member_key = create_api_key(@member, "read_write")
  end

  teardown do
    ApiKey.where(user: [ @admin, @member, family_guest ]).find_each do |key|
      Redis.new.del("api_rate_limit:#{key.id}")
    end
  end

  test "show returns the prompts, the classifier and whether AI is available" do
    @family.update!(ai_prompt_chat_system: "Be brief.")
    Setting.stubs(:openai_access_token).returns("sk-secret-should-not-leak")

    get api_v1_settings_ai_url, headers: api_headers(@read_key)

    assert_response :success
    body = JSON.parse(response.body)["ai_settings"]
    assert_equal @admin.ai_available?, body["ai_available"]
    assert_equal @admin.ai_enabled?, body["ai_enabled"]
    assert_equal Family::AiPromptable::MAX_LENGTH, body["prompt_max_length"]
    assert_equal Family::AiPromptable::KEYS.map(&:to_s), body["prompts"].map { |prompt| prompt["key"] }

    chat = body["prompts"].find { |prompt| prompt["key"] == "chat_system" }
    assert_equal "Be brief.", chat["value"]
    assert_equal true, chat["custom"]
    assert_equal @family.ai_prompt_default(:chat_system), chat["default"]

    merchant = body["prompts"].find { |prompt| prompt["key"] == "merchant_openai" }
    assert_nil merchant["value"]
    assert_equal false, merchant["custom"]
    assert_equal "merchants", merchant["format_risk_key"]

    classifier = body["classifier"]
    assert_equal 0.7, classifier["settings"]["threshold"]
    assert_equal true, classifier["default"]
    assert_equal({ "min" => 0.05, "max" => 0.99 }, classifier["ranges"]["threshold"])
    assert_equal %w[ascii unicode symbols], classifier["choices"]["word_split"]
    assert_equal Family::CLASSIFIER_ACTION_TYPES, classifier["rules"].map { |rule| rule["action_type"] }
    assert classifier["rules"].all? { |rule| rule["exists"] == false && rule["active"] == false }
    assert_equal false, classifier["evaluation"]["running"]
    assert_nil classifier["evaluation"]["ran_at"]

    assert_not_includes response.body, "sk-secret-should-not-leak"
  end

  test "show needs an API key" do
    get api_v1_settings_ai_url

    assert_response :unauthorized
  end

  test "every action needs a family admin, as on the web" do
    guest_key = create_api_key(family_guest, "read_write")

    [ @member_key, guest_key ].each do |key|
      get api_v1_settings_ai_url, headers: api_headers(key)
      assert_response :forbidden
      assert_equal "forbidden", JSON.parse(response.body)["error"]

      patch api_v1_settings_ai_url, params: { ai_settings: { prompts: { chat_system: "x" } } }.to_json, headers: json_headers(key)
      assert_response :forbidden

      get api_v1_settings_ai_usage_url, headers: api_headers(key)
      assert_response :forbidden

      assert_no_enqueued_jobs do
        post api_v1_settings_ai_classifier_run_url, headers: api_headers(key)
        assert_response :forbidden
        post api_v1_settings_ai_classifier_clear_locks_url, headers: api_headers(key)
        assert_response :forbidden
      end

      post api_v1_settings_ai_classifier_rules_url, params: { action_type: "bayes_categorize" }.to_json, headers: json_headers(key)
      assert_response :forbidden
    end

    assert_nil @family.reload.ai_prompt(:chat_system)
  end

  test "writes need the read_write scope" do
    patch api_v1_settings_ai_url, params: { ai_settings: { prompts: { chat_system: "x" } } }.to_json, headers: json_headers(@read_key)
    assert_response :forbidden
    assert_equal "insufficient_scope", JSON.parse(response.body)["error"]

    assert_no_enqueued_jobs do
      post api_v1_settings_ai_classifier_run_url, headers: api_headers(@read_key)
    end
    assert_response :forbidden
  end

  test "update sets a prompt override and a blank one resets it" do
    patch api_v1_settings_ai_url, params: { ai_settings: { prompts: { chat_system: "Be brief.", insight_dig_in: "Dig." } } }.to_json,
      headers: json_headers(@write_key)

    assert_response :success
    assert_equal "Be brief.", @family.reload.ai_prompt(:chat_system)
    assert_equal "Dig.", @family.ai_prompt(:insight_dig_in)
    chat = JSON.parse(response.body)["ai_settings"]["prompts"].find { |prompt| prompt["key"] == "chat_system" }
    assert_equal "Be brief.", chat["value"]

    patch api_v1_settings_ai_url, params: { ai_settings: { prompts: { chat_system: "", insight_dig_in: nil } } }.to_json,
      headers: json_headers(@write_key)

    assert_response :success
    assert_equal({}, @family.reload.ai_prompt_overrides)
  end

  test "update rejects a prompt over the limit, an unknown prompt and a non-string" do
    patch api_v1_settings_ai_url, params: { ai_settings: { prompts: { chat_system: "a" * (Family::AiPromptable::MAX_LENGTH + 1) } } }.to_json,
      headers: json_headers(@write_key)
    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "validation_failed", body["error"]
    assert body["errors"].any?

    patch api_v1_settings_ai_url, params: { ai_settings: { prompts: { system_secret: "x" } } }.to_json, headers: json_headers(@write_key)
    assert_response :unprocessable_entity
    assert_match "system_secret", JSON.parse(response.body)["message"]

    patch api_v1_settings_ai_url, params: { ai_settings: { prompts: { chat_system: 5 } } }.to_json, headers: json_headers(@write_key)
    assert_response :unprocessable_entity

    patch api_v1_settings_ai_url, params: { ai_settings: { other: 1 } }.to_json, headers: json_headers(@write_key)
    assert_response :unprocessable_entity

    assert_equal({}, @family.reload.ai_prompt_overrides)
  end

  test "update changes only the classifier settings it is sent" do
    @family.update_bayes_settings!(bigrams: true)
    category = @family.categories.first

    patch api_v1_settings_ai_url,
      params: { ai_settings: { classifier: { settings: { threshold: 0.6, word_split: "unicode", excluded_category_ids: [ category.id ] } } } }.to_json,
      headers: json_headers(@write_key)

    assert_response :success
    settings = @family.reload.bayes_settings_object
    assert_equal 0.6, settings.threshold
    assert_equal "unicode", settings.word_split
    assert_equal true, settings.bigrams
    assert_equal [ category.id ], settings.excluded_category_ids
    assert_equal false, JSON.parse(response.body)["ai_settings"]["classifier"]["default"]
  end

  test "update clamps a classifier number to its range, as the web form does" do
    patch api_v1_settings_ai_url, params: { ai_settings: { classifier: { settings: { threshold: 5 } } } }.to_json,
      headers: json_headers(@write_key)

    assert_response :success
    assert_equal 0.99, @family.reload.bayes_settings_object.threshold
  end

  test "update rejects another family's category, an unknown setting and a wrong type" do
    other_category = @other_family.categories.create!(name: "Theirs #{SecureRandom.hex(3)}", color: "#000000")

    patch api_v1_settings_ai_url, params: { ai_settings: { classifier: { settings: { excluded_category_ids: [ other_category.id ] } } } }.to_json,
      headers: json_headers(@write_key)
    assert_response :unprocessable_entity
    assert_match other_category.id, JSON.parse(response.body)["message"]

    patch api_v1_settings_ai_url, params: { ai_settings: { classifier: { settings: { nope: 1 } } } }.to_json, headers: json_headers(@write_key)
    assert_response :unprocessable_entity

    patch api_v1_settings_ai_url, params: { ai_settings: { classifier: { settings: { threshold: [ 1 ] } } } }.to_json, headers: json_headers(@write_key)
    assert_response :unprocessable_entity

    assert_equal({}, @family.reload.bayes_settings)
  end

  test "update switches a classifier rule, and asks to add one that was deleted" do
    @family.add_classifier_rule!("bayes_categorize")

    patch api_v1_settings_ai_url, params: { ai_settings: { classifier: { rules_active: { bayes_categorize: false } } } }.to_json,
      headers: json_headers(@write_key)
    assert_response :success
    assert_not @family.classifier_rule_active?("bayes_categorize")

    patch api_v1_settings_ai_url, params: { ai_settings: { classifier: { rules_active: { bayes_categorize: true, fill_similar_merchants: true } } } }.to_json,
      headers: json_headers(@write_key)
    assert_response :unprocessable_entity
    assert_equal "classifier_rule_missing", JSON.parse(response.body)["error"]
    assert_not @family.classifier_rule_active?("bayes_categorize")

    patch api_v1_settings_ai_url, params: { ai_settings: { classifier: { rules_active: { bayes_categorize: "maybe" } } } }.to_json,
      headers: json_headers(@write_key)
    assert_response :unprocessable_entity
  end

  test "add a deleted classifier rule again" do
    assert_difference -> { @family.rules.count }, 1 do
      post api_v1_settings_ai_classifier_rules_url, params: { action_type: "fill_similar_merchants" }.to_json, headers: json_headers(@write_key)
    end
    assert_response :created
    rule = JSON.parse(response.body)["ai_settings"]["classifier"]["rules"].find { |row| row["action_type"] == "fill_similar_merchants" }
    assert_equal true, rule["exists"]
    assert_equal true, rule["active"]

    post api_v1_settings_ai_classifier_rules_url, params: { action_type: "fill_similar_merchants" }.to_json, headers: json_headers(@write_key)
    assert_response :conflict

    post api_v1_settings_ai_classifier_rules_url, params: { action_type: "nope" }.to_json, headers: json_headers(@write_key)
    assert_response :unprocessable_entity
  end

  test "run queues the classifier as the web does" do
    assert_enqueued_with(job: BayesCategorizeJob, args: [ @family ]) do
      post api_v1_settings_ai_classifier_run_url, headers: api_headers(@write_key)
    end

    assert_response :accepted
    assert_equal({ "status" => "queued", "job" => "classifier_run" }, JSON.parse(response.body)["data"])
  end

  test "clear_locks queues the unlock job as the web does" do
    assert_enqueued_with(job: ClearBayesLocksJob, args: [ @family ]) do
      post api_v1_settings_ai_classifier_clear_locks_url, headers: api_headers(@write_key)
    end

    assert_response :accepted
    assert_equal({ "status" => "queued", "job" => "classifier_clear_locks" }, JSON.parse(response.body)["data"])
  end

  test "usage totals the web's numbers per model and per day" do
    travel_to Time.zone.parse("2026-03-10 12:00") do
      create_usage(model: "gpt-4.1", cost: 0.012345, tokens: [ 100, 50 ], at: 2.days.ago)
      create_usage(model: "gpt-4.1", cost: 0.5, tokens: [ 200, 100 ], at: 1.day.ago)
      create_usage(model: "local-llama", cost: nil, tokens: [ 10, 5 ], at: 1.day.ago)
      create_usage(model: "gpt-4.1", cost: 9, tokens: [ 1, 1 ], at: 60.days.ago)
      LlmUsage.create!(family: @other_family, provider: "openai", model: "gpt-4.1", operation: "chat",
        prompt_tokens: 1, completion_tokens: 1, total_tokens: 2, estimated_cost: 7)

      get api_v1_settings_ai_usage_url, headers: api_headers(@read_key)
    end

    assert_response :success
    usage = JSON.parse(response.body)["llm_usage"]
    assert_equal "2026-02-08", usage["start_date"]
    assert_equal "2026-03-10", usage["end_date"]
    assert_equal "USD", usage["currency"]
    assert_equal 3, usage["total_requests"]
    assert_equal 2, usage["requests_with_cost"]
    assert_equal 465, usage["total_tokens"]
    assert_equal "$0.51", usage["total_cost"]
    assert_equal 51, usage["total_cost_cents"]

    gpt = usage["by_model"].first
    assert_equal "gpt-4.1", gpt["model"]
    assert_equal 2, gpt["total_requests"]
    assert_equal "$0.5123", gpt["cost"]
    assert_equal 51, gpt["cost_cents"]
    assert_equal "0.512345", gpt["cost_amount"]
    llama = usage["by_model"].last
    assert_equal 0, llama["requests_with_cost"]
    assert_equal "$0.0000", llama["cost"]

    assert_equal %w[2026-03-08 2026-03-09], usage["by_day"].map { |day| day["date"] }
    assert_equal [ 1, 2 ], usage["by_day"].map { |day| day["total_requests"] }
    assert_equal [ "chat" ], usage["by_operation"].map { |row| row["operation"] }
  end

  test "usage takes a date range and rejects a bad one" do
    create_usage(model: "gpt-4.1", cost: 9, tokens: [ 1, 1 ], at: Time.zone.parse("2025-01-15 12:00"))

    get api_v1_settings_ai_usage_url, params: { start_date: "2025-01-01", end_date: "2025-01-31" }, headers: api_headers(@read_key)
    assert_response :success
    assert_equal 1, JSON.parse(response.body)["llm_usage"]["total_requests"]

    get api_v1_settings_ai_usage_url, params: { start_date: "2025-13-01" }, headers: api_headers(@read_key)
    assert_response :unprocessable_entity

    get api_v1_settings_ai_usage_url, params: { start_date: "2025-02-01", end_date: "2025-01-01" }, headers: api_headers(@read_key)
    assert_response :unprocessable_entity
    assert_equal "validation_failed", JSON.parse(response.body)["error"]
  end

  private

    def create_api_key(user, scope)
      ApiKey.create!(user: user, name: "AI settings #{scope} #{SecureRandom.hex(3)}", scopes: [ scope ],
        display_key: "test_ai_#{SecureRandom.hex(8)}", source: scope == "read" ? "mobile" : "web")
    end

    def create_usage(model:, cost:, tokens:, at:)
      prompt_tokens, completion_tokens = tokens
      LlmUsage.create!(family: @family, provider: "openai", model: model, operation: "chat",
        prompt_tokens: prompt_tokens, completion_tokens: completion_tokens, total_tokens: prompt_tokens + completion_tokens,
        estimated_cost: cost, created_at: at)
    end

    def api_headers(api_key)
      { "X-Api-Key" => api_key.display_key }
    end

    def json_headers(api_key)
      api_headers(api_key).merge("Content-Type" => "application/json")
    end
end
