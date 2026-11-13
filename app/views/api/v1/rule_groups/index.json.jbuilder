# frozen_string_literal: true

json.data @rule_groups do |rule_group|
  json.partial! "api/v1/rule_groups/rule_group", rule_group: rule_group, rules_counts: @rules_counts
end
