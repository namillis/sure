# frozen_string_literal: true

json.data do
  json.partial! "api/v1/rule_runs/rule_run", rule_run: @rule_run
end
