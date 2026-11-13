# frozen_string_literal: true

json.from do
  json.partial! "api/v1/budget_categories/budget_category", budget_category: @from
end

json.to do
  json.partial! "api/v1/budget_categories/budget_category", budget_category: @to
end

json.budget do
  json.partial! "api/v1/budgets/budget", budget: @budget
end
