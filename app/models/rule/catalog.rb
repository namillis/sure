# The conditions and actions a rule of one resource type can use, as the web
# rule form offers them: read from the resource's registry, so a filter or
# executor added there shows up here without a second list.
class Rule::Catalog
  def initialize(family:, resource_type:)
    @resource_type = resource_type
    @registry = Rule.new(family: family, resource_type: resource_type).registry
  end

  def as_json(*)
    offered_action_keys = registry.action_executors.map(&:key)
    ai_action_keys = registry.class::AI_ACTION_KEYS

    {
      resource_type: resource_type,
      ai_available: ai_action_keys.any? { |key| offered_action_keys.include?(key) },
      conditions: registry.condition_filters.map { |filter| condition_json(filter) },
      actions: registry.known_action_executors.map do |executor|
        action_json(executor, available: offered_action_keys.include?(executor.key), requires_ai: ai_action_keys.include?(executor.key))
      end
    }
  end

  private
    attr_reader :resource_type, :registry

    def condition_json(filter)
      {
        key: filter.key,
        label: filter.label,
        type: filter.type,
        operators: filter.operators.map do |label, key|
          { key: key, label: label, requires_value: Rule::ConditionFilter::VALUELESS_OPERATORS.exclude?(key) }
        end,
        options: options_json(filter.options),
        number_step: filter.type == "number" ? filter.number_step : nil
      }
    end

    def action_json(executor, available:, requires_ai:)
      {
        key: executor.key,
        label: executor.label,
        value_type: executor.type,
        options: options_json(executor.options),
        requires_ai: requires_ai,
        available: available
      }
    end

    def options_json(options)
      options&.map { |label, value| { value: value, label: label } }
    end
end
