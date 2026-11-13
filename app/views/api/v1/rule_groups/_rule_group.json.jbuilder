# frozen_string_literal: true

json.id rule_group.id
json.name rule_group.name
json.position rule_group.position
json.rules_count rules_counts.fetch(rule_group.id, 0)
json.created_at rule_group.created_at.iso8601
json.updated_at rule_group.updated_at.iso8601
