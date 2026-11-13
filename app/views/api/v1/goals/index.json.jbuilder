# frozen_string_literal: true

json.goals @goals do |goal|
  json.partial! "api/v1/goals/goal", goal: goal, accessible_account_ids: @accessible_account_ids
end
