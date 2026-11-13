# frozen_string_literal: true

json.rules @rules do |rule|
  json.partial! "api/v1/rules/rule", rule: rule
end
