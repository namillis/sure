# frozen_string_literal: true

json.partial! "api/v1/goals/goal", goal: @goal, accessible_account_ids: @accessible_account_ids
