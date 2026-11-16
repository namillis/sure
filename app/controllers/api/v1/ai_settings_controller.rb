# frozen_string_literal: true

# Settings → AI prompts, Settings → Classifier and Settings → LLM usage. Every
# one of those web pages is admin-only, so every action here is too.
class Api::V1::AiSettingsController < Api::V1::BaseController
  READ_ACTIONS = %i[show usage].freeze

  before_action -> { authorize_scope!(:read) }, only: READ_ACTIONS
  before_action -> { authorize_scope!(:read_write) }, except: READ_ACTIONS
  before_action :require_family_admin
  before_action -> { @user = current_resource_owner }

  def show
    @family = family
  end

  def update
    changes = parse_update_params
    return if performed?

    missing_rule = changes[:rules_active].find { |action_type, active| active && !family.classifier_rules(action_type).exists? }&.first
    if missing_rule
      return render_json({
        error: "classifier_rule_missing",
        message: "The #{Family.classifier_rule_name(missing_rule)} rule was deleted. Add it again with POST /api/v1/settings/ai/classifier/rules.",
        errors: [ "rules_active.#{missing_rule}" ]
      }, status: :unprocessable_entity)
    end

    Family.transaction do
      family.update!(changes[:prompts].transform_keys { |key| :"ai_prompt_#{key}" }) if changes[:prompts].any?
      family.update_bayes_settings!(changes[:settings]) if changes[:settings].any?
      changes[:rules_active].each { |action_type, active| family.set_classifier_rule_active!(action_type, active) }
    end

    @family = family.reload
    render :show
  rescue ActiveRecord::RecordInvalid => e
    messages = e.record.errors.full_messages
    render_json({ error: "validation_failed", message: messages.to_sentence, errors: messages }, status: :unprocessable_entity)
  end

  def run_classifier
    enqueue(BayesCategorizeJob, "classifier_run")
  end

  def clear_classifier_locks
    enqueue(ClearBayesLocksJob, "classifier_clear_locks")
  end

  # The web's "add it again?" dialog, for a classifier rule that was deleted.
  def add_classifier_rule
    action_type = params[:action_type].presence_in(Family::CLASSIFIER_ACTION_TYPES)
    return render_validation_error("action_type must be one of: #{Family::CLASSIFIER_ACTION_TYPES.join(", ")}") unless action_type

    if family.classifier_rules(action_type).exists?
      return render_json({ error: "classifier_rule_exists", message: "#{Family.classifier_rule_name(action_type)} already has a rule" },
        status: :conflict)
    end

    family.add_classifier_rule!(action_type)
    @family = family.reload
    render :show, status: :created
  end

  def usage
    @end_date = params[:end_date].present? ? parse_date(params[:end_date]) : Date.current
    return render_validation_error("end_date must be a YYYY-MM-DD date") unless @end_date

    @start_date = params[:start_date].present? ? parse_date(params[:start_date]) : @end_date - 30.days
    return render_validation_error("start_date must be a YYYY-MM-DD date") unless @start_date
    return render_validation_error("start_date must be on or before end_date") if @start_date > @end_date

    @report = LlmUsage::Report.new(family, start_date: @start_date, end_date: @end_date)
  end

  private

    def family
      current_resource_owner.family
    end

    def require_family_admin
      return if current_resource_owner.admin?

      render_json({ error: "forbidden", message: "AI settings require a family admin" }, status: :forbidden)
    end

    def enqueue(job_class, job_name)
      unless job_class.perform_later(family)
        return render_json({ error: "enqueue_failed", message: "The job could not be queued. Try again shortly." },
          status: :service_unavailable)
      end

      render_json({ data: { status: "queued", job: job_name } }, status: :accepted)
    end

    # { prompts: { key => text }, settings: { key => value }, rules_active: { action_type => bool } },
    # or renders a 422 naming the first field it can't take.
    def parse_update_params
      body = params.require(:ai_settings)
      return render_validation_error("ai_settings must be an object") unless body.is_a?(ActionController::Parameters)

      prompts = parse_prompts(body[:prompts])
      return if performed?

      classifier = body[:classifier]
      if classifier.present? && !classifier.is_a?(ActionController::Parameters)
        return render_validation_error("classifier must be an object")
      end

      settings = parse_classifier_settings(classifier&.dig(:settings))
      return if performed?

      rules_active = parse_rules_active(classifier&.dig(:rules_active))
      return if performed?

      if prompts.empty? && settings.empty? && rules_active.empty?
        return render_validation_error("Send prompts, classifier.settings or classifier.rules_active")
      end

      { prompts: prompts, settings: settings, rules_active: rules_active }
    end

    # A blank or null prompt resets it to the default, as clearing the web field does.
    def parse_prompts(prompts)
      return {} if prompts.nil?
      return render_validation_error("prompts must be an object") unless prompts.is_a?(ActionController::Parameters)

      allowed = Family::AiPromptable::KEYS.map(&:to_s)
      unknown = prompts.keys - allowed
      return render_validation_error("Unknown prompts: #{unknown.join(", ")}. Allowed: #{allowed.join(", ")}") if unknown.any?

      invalid = prompts.keys.reject { |key| prompts[key].nil? || prompts[key].is_a?(String) }
      return render_validation_error("prompts.#{invalid.first} must be a string or null") if invalid.any?

      prompts.permit(*allowed).to_h
    end

    # Values are cast and clamped to their ranges by Family::BayesSettings, as
    # the web's form values are.
    def parse_classifier_settings(settings)
      return {} if settings.nil?
      return render_validation_error("classifier.settings must be an object") unless settings.is_a?(ActionController::Parameters)

      allowed = Family::BayesSettings::DEFAULTS.keys.map(&:to_s)
      unknown = settings.keys - allowed
      return render_validation_error("Unknown classifier settings: #{unknown.join(", ")}") if unknown.any?

      scalar_keys = Family::BayesSettings::DEFAULTS.reject { |_, default| default.is_a?(Array) }.keys
      permitted = settings.permit(*scalar_keys, excluded_category_ids: []).to_h
      dropped = settings.keys - permitted.keys
      return render_validation_error("classifier.settings.#{dropped.first} has the wrong type") if dropped.any?

      if permitted.key?("excluded_category_ids")
        ids = permitted["excluded_category_ids"].map(&:to_s)
        unknown_ids = ids - family.categories.where(id: ids.select { |id| valid_uuid?(id) }).pluck(:id).map(&:to_s)
        return render_validation_error("excluded_category_ids has categories this family doesn't have: #{unknown_ids.join(", ")}") if unknown_ids.any?
      end

      permitted
    end

    def parse_rules_active(rules_active)
      return {} if rules_active.nil?
      return render_validation_error("classifier.rules_active must be an object") unless rules_active.is_a?(ActionController::Parameters)

      unknown = rules_active.keys - Family::CLASSIFIER_ACTION_TYPES
      return render_validation_error("Unknown classifier rules: #{unknown.join(", ")}") if unknown.any?

      rules_active.keys.to_h do |action_type|
        value = rules_active[action_type]
        return render_validation_error("classifier.rules_active.#{action_type} must be true or false") unless value.in?([ true, false, "true", "false" ])

        [ action_type, ActiveModel::Type::Boolean.new.cast(value) ]
      end
    end
end
