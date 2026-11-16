# frozen_string_literal: true

# Estimated costs are in USD. The formatted strings use the web page's
# precision: 2 decimals for the total, 4 for everything else; `_amount` is
# the unrounded decimal, since most single requests cost under a cent.
cost_fields = lambda do |json, name, amount, decimals|
  amount = amount.to_d
  json.set! name, format("$%.#{decimals}f", amount)
  json.set! "#{name}_cents", (amount * 100).round(0).to_i
  json.set! "#{name}_amount", amount.to_s("F")
end

counts = lambda do |json, totals|
  json.total_requests totals[:total_requests]
  json.requests_with_cost totals[:requests_with_cost]
  json.total_prompt_tokens totals[:total_prompt_tokens]
  json.total_completion_tokens totals[:total_completion_tokens]
  json.total_tokens totals[:total_tokens]
end

statistics = @report.statistics

json.llm_usage do
  json.start_date @report.start_date
  json.end_date @report.end_date
  json.currency "USD"

  counts.call(json, statistics)
  cost_fields.call(json, :total_cost, statistics[:total_cost], 2)
  cost_fields.call(json, :avg_cost, statistics[:avg_cost], 4)

  json.by_operation statistics[:by_operation].sort_by { |operation, cost| [ -cost, operation ] } do |operation, cost|
    json.operation operation
    json.label operation.humanize
    cost_fields.call(json, :cost, cost, 4)
  end

  json.by_model @report.by_model do |row|
    json.model row[:model]
    counts.call(json, row)
    cost_fields.call(json, :cost, row[:cost], 4)
  end

  json.by_day @report.by_day do |row|
    json.date row[:date]
    counts.call(json, row)
    cost_fields.call(json, :cost, row[:cost], 4)
  end
end
