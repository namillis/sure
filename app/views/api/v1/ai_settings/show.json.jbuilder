# frozen_string_literal: true

settings = @family.bayes_settings_object
evaluation = Family::BayesEvaluation.cached(@family)

json.ai_settings do
  json.ai_available @user.ai_available?
  json.ai_enabled @user.ai_enabled?

  json.prompt_max_length Family::AiPromptable::MAX_LENGTH
  json.prompts Family::AiPromptable::KEYS do |key|
    override = @family.ai_prompt(key)
    json.key key
    json.value override
    json.default @family.ai_prompt_default(key)
    json.custom override.present?
    json.format_risk @family.ai_prompt_format_risk?(key)
    json.format_risk_key Family::AiPromptable::WRAPPER_KEYS[key]
  end

  json.classifier do
    json.settings settings.values
    json.defaults Family::BayesSettings::DEFAULTS
    json.default settings.default?
    json.ranges(Family::BayesSettings::RANGES.transform_values { |range| { min: range.min, max: range.max } })
    json.choices Family::BayesSettings::CHOICES
    json.rules Family::CLASSIFIER_ACTION_TYPES do |action_type|
      json.action_type action_type
      json.name Family.classifier_rule_name(action_type)
      json.exists @family.classifier_rules(action_type).exists?
      json.active @family.classifier_rule_active?(action_type)
    end
    json.evaluation do
      json.running Family::BayesEvaluation.running?(@family)
      json.ran_at evaluation&.dig("ran_at")
      json.action evaluation&.dig("action")
      json.settings_changed_since(evaluation ? evaluation["digest"] != settings.digest : nil)
    end
  end
end
