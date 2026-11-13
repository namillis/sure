# frozen_string_literal: true

json.pledge do
  json.partial! "api/v1/goals/pledge", pledge: @pledge, accessible_account_ids: @accessible_account_ids
end
json.goal do
  json.partial! "api/v1/goals/goal", goal: @goal, accessible_account_ids: @accessible_account_ids
end
