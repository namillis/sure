# frozen_string_literal: true

class Api::V1::RulesController < Api::V1::BaseController
  include Pagy::Backend

  BOOLEAN_FILTERS = {
    "true" => true,
    "1" => true,
    "false" => false,
    "0" => false
  }.freeze
  RESOURCE_TYPES = %w[transaction].freeze
  CONDITION_FIELDS = %i[id condition_type operator value _destroy].freeze
  ACTION_FIELDS = [
    :id, :action_type, :value, :_destroy, { value: [] },
    { split_rows: [ :type, :name, :share, :category_id, :merchant_id, { tag_ids: [] } ] }
  ].freeze

  RULE_INCLUDES = [ :actions, :rule_group, { conditions: :sub_conditions } ].freeze

  before_action :ensure_read_scope, only: %i[index show]
  before_action -> { authorize_scope!(:read_write) }, only: %i[create update destroy apply reorder]
  before_action :reject_guest_writes!, only: %i[create update destroy apply reorder]
  before_action :set_rule, only: %i[show update destroy apply]

  def index
    return render_invalid_resource_type_filter if invalid_resource_type_filter?

    @per_page = safe_per_page_param
    rules_query = current_resource_owner.family.rules.includes(*RULE_INCLUDES).ordered

    rules_query = rules_query.where(resource_type: params[:resource_type]) if params[:resource_type].present?
    if params[:active].present?
      active = parse_boolean_filter(params[:active])
      return if performed?

      rules_query = rules_query.where(active: active)
    end

    @pagy, @rules = pagy(
      rules_query,
      page: safe_page_param,
      limit: @per_page
    )

    render :index
  end

  def show
    render :show
  end

  def create
    @rule = current_resource_owner.family.rules.build
    return unless assign_rule_attributes

    @rule.resource_type = "transaction" if @rule.resource_type.blank?
    render_saved_rule(status: :created)
  end

  def update
    return unless assign_rule_attributes

    render_saved_rule(status: :ok)
  end

  def destroy
    @rule.destroy!
    head :no_content
  end

  # Same order the web's drag and drop sets (Rule::Layout), sent as the whole
  # flat list of the family's rules.
  def reorder
    Rule::FlatReorder.new(current_resource_owner.family).reorder!(params.require(:rule_ids))
    @rules = current_resource_owner.family.rules.includes(*RULE_INCLUDES).ordered
    render :reorder
  rescue ArgumentError => e
    render_validation_error(e.message)
  end

  # The web shows a confirmation (affected count, rules above, AI cost) before
  # every apply, so the API asks for confirm: true and otherwise returns what
  # that dialog shows.
  def apply
    unless ActiveModel::Type::Boolean.new.cast(params[:confirm]) == true
      return render_confirmation_required
    end

    unless @rule.update(active: true)
      return render_rule_errors
    end

    if @rule.notification_baseline_timed_out?
      return render_json({
        error: "notification_baseline_timed_out",
        message: notification_baseline_timed_out_message,
        errors: [ notification_baseline_timed_out_message ]
      }, status: :unprocessable_entity)
    end

    rule_runs = Rule::Runner.new(
      @rule.family,
      rules: [ @rule ],
      execution_type: "manual",
      ignore_attribute_locks: true
    ).run

    @rule_run = rule_runs.last
    render :apply, status: :created
  rescue Rule::Runner::LockBusy
    render_json({
      error: "rules_running",
      message: "Rules are already running for this family. Try again shortly."
    }, status: :conflict)
  end

  private

    def set_rule
      @rule = current_resource_owner.family.rules.includes(*RULE_INCLUDES).find(params[:id])
    end

    def ensure_read_scope
      authorize_scope!(:read)
    end

    def parse_boolean_filter(value)
      normalized = value.to_s.downcase
      return BOOLEAN_FILTERS[normalized] if BOOLEAN_FILTERS.key?(normalized)

      render_validation_error("active must be one of: true, false, 1, 0")
      nil
    end

    def invalid_resource_type_filter?
      params[:resource_type].present? && !params[:resource_type].in?(RESOURCE_TYPES)
    end

    def render_invalid_resource_type_filter
      render_validation_error("resource_type must be one of: #{RESOURCE_TYPES.join(", ")}")
    end

    # A nested id that is not part of this rule makes nested attributes raise
    # RecordNotFound, which is a bad request body here rather than a missing rule.
    def assign_rule_attributes
      @rule.assign_attributes(rule_attributes)
      true
    rescue ActiveRecord::RecordNotFound => e
      render_validation_error(e.message)
      false
    end

    def render_saved_rule(status:)
      return render_rule_errors unless save_rule

      @warnings = @rule.notification_baseline_timed_out? ? [ notification_baseline_timed_out_message ] : []
      @rule = current_resource_owner.family.rules.includes(*RULE_INCLUDES).find(@rule.id)
      render :saved, status: status
    end

    # Same retry as the web: a group named in new_rule_group_name may be created
    # by another request at the same moment.
    def save_rule
      @rule.save
    rescue ActiveRecord::RecordNotUnique
      raise unless @rule.rule_group&.new_record?

      @rule.save
    end

    def render_rule_errors
      messages = @rule.errors.full_messages
      render_json({
        error: "validation_failed",
        message: messages.to_sentence,
        errors: messages
      }, status: :unprocessable_entity)
    end

    def render_confirmation_required
      message = "Applying a rule changes existing transactions. Send confirm: true to apply it."
      render_json({
        error: "confirmation_required",
        message: message,
        errors: [ message ],
        confirmation: confirmation_details
      }, status: :unprocessable_entity)
    end

    def confirmation_details
      affected_count = @rule.affected_resource_count
      auto_categorize = @rule.actions.any? { |action| action.action_type == "auto_categorize" }
      model, cost = auto_categorize ? auto_categorize_estimate(affected_count) : [ nil, nil ]

      {
        affected_resource_count: affected_count,
        resource_type: @rule.resource_type,
        active_rules_above_count: @rule.active_rules_above.count,
        auto_categorize: auto_categorize,
        ai_model: model,
        estimated_ai_cost: cost
      }
    end

    # Same estimate as RulesController#auto_categorize_estimate (the web confirm dialog).
    def auto_categorize_estimate(transaction_count)
      family = @rule.family
      model = family.categorization_model_name
      return [ nil, nil ] if model.blank?

      cost = LlmUsage.estimate_auto_categorize_cost(
        transaction_count: transaction_count,
        category_count: family.categories.count,
        model: model
      )

      [ model, cost ]
    end

    def notification_baseline_timed_out_message
      I18n.t("rules.notification_baseline_timed_out")
    end

    # Takes conditions and actions in the shape GET /rules/:id returns. When a
    # list is sent it is the rule's whole list: saved entries left out of it are
    # removed. A list that is omitted leaves the saved entries as they are.
    def rule_attributes
      permitted = params.require(:rule).permit(
        :name, :resource_type, :active, :effective_date, :stop_processing,
        :rule_group_id, :new_rule_group_name,
        conditions: [ *CONDITION_FIELDS, { sub_conditions: CONDITION_FIELDS } ],
        actions: ACTION_FIELDS
      ).to_h

      conditions = permitted.delete("conditions")
      actions = permitted.delete("actions")

      if conditions
        existing_conditions = @rule.new_record? ? [] : @rule.conditions.to_a
        permitted["conditions_attributes"] = conditions_attributes(conditions, existing_conditions)
      end

      if actions
        existing_actions = @rule.new_record? ? [] : @rule.actions.to_a
        permitted["actions_attributes"] = with_removals(rows_for(actions), existing_actions)
      end

      permitted
    end

    def conditions_attributes(conditions, existing_conditions)
      rows = rows_for(conditions).map do |row|
        sub_conditions = row.delete("sub_conditions")
        next row if sub_conditions.nil?

        parent = existing_conditions.find { |condition| condition.id == row["id"] }
        row.merge("sub_conditions_attributes" => with_removals(rows_for(sub_conditions), parent ? parent.sub_conditions.to_a : []))
      end

      with_removals(rows, existing_conditions)
    end

    def rows_for(list)
      rows = Array(list).map(&:dup)
      rows.each { |row| row.delete("id") } if @rule.new_record?
      rows
    end

    def with_removals(rows, existing_records)
      kept_ids = rows.filter_map { |row| row["id"] }
      removed = existing_records.reject { |record| kept_ids.include?(record.id) }
      rows + removed.map { |record| { "id" => record.id, "_destroy" => "1" } }
    end
end
